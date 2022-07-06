#!/usr/bin/env bash

#######################################################################
# This script performs deployment of ECS Service using AWS CodeDeploy
#
# Heavily inspired by https://github.com/silinternational/ecs-deploy ,
# which unfortunately can't be used to deploy ECS service when `deployment_option=ECS`
#
# Author: Anton Babenko
# URL: https://github.com/antonbabenko
# Gist:
#######################################################################

set -e

#set -x

####################################################################
# DO NOT TOUCH BELOW THIS LINE if you don't know what you are doing
####################################################################

readonly APPSPEC_FILENAME="appspec.yaml"
readonly TASK_DEF_FILENAME="taskdef.json"

function print_usage {
  echo
  echo "Usage: ecs-codedeploy [OPTIONS]"
  echo
  echo "This script performs deployment of ECS Service using AWS CodeDeploy."
  echo "Heavily inspired by 'ecs-deploy' script, which unfortunately can't deploy ECS service when it has 'deployment_option=ECS'."
  echo
  echo "An error occurred (InvalidParameterException) when calling the UpdateService operation:"
  echo "Unable to update task definition on services with a CODE_DEPLOY deployment controller. Please use Code Deploy to trigger a new deployment."
  echo
  echo "'aws ecs deploy' should be used, as described here: https://docs.aws.amazon.com/cli/latest/reference/ecs/deploy/index.html"
  echo
  echo "Required arguments:"
  echo
  echo -e "  --cluster\t\t\tName of ECS Cluster"
  echo -e "  --service\t\t\tName of ECS Service to update"
  echo -e "  --image\t\t\tImage ID to deploy (eg, 640673857988.dkr.ecr.eu-central-1.amazonaws.com/backend:v1.2.3)"
  echo
  echo "Optional arguments:"
  echo
  echo -e "  --iam-role\t\t\tAWS IAM role to assume before deployment"
  echo -e "  --from-current-task\t\t\tGet current task or latest as a base (default: latest)"
  echo
  echo "Examples:"
  echo
  echo "  ecs-codedeploy --iam-role arn:aws:iam::604506250246:role/ecs-deploy --cluster production --service backend --image 640673857988.dkr.ecr.eu-central-1.amazonaws.com/backend:v1.2.3"
}

function assert_not_empty {
  local readonly arg_name="$1"
  local readonly arg_value="$2"

  if [[ -z "$arg_value" ]]; then
    echo "ERROR: The value for '$arg_name' cannot be empty"
    print_usage
    exit 1
  fi
}

function assert_is_installed {
  local readonly name="$1"

  if [[ ! $(command -v ${name}) ]]; then
    echo "ERROR: The binary '$name' is required by this script but is not installed or in the system's PATH."
    exit 1
  fi
}

function assumeRole() {
  temp_role=$(aws sts assume-role \
                  --role-arn "${AWS_ASSUME_ROLE}" \
                  --role-session-name "$(date +"%s")")

  export AWS_ACCESS_KEY_ID=$(echo $temp_role | jq .Credentials.AccessKeyId | xargs)
  export AWS_SECRET_ACCESS_KEY=$(echo $temp_role | jq .Credentials.SecretAccessKey | xargs)
  export AWS_SESSION_TOKEN=$(echo $temp_role | jq .Credentials.SessionToken | xargs)
}

function assumeRoleClean() {
  unset AWS_ACCESS_KEY_ID
  unset AWS_SECRET_ACCESS_KEY
  unset AWS_SESSION_TOKEN
}

function get_current_task_definition() {
  TASK_DEFINITION_ARN=$(aws ecs describe-services --services "$service" --cluster "$cluster" | jq -r ".services[0].taskDefinition")
  TASK_DEFINITION=$(aws ecs describe-task-definition --task-def "$TASK_DEFINITION_ARN")
}

function get_latest_task_definition() {
  TASK_DEFINITION=$(aws ecs describe-task-definition --task-def "$service")
  TASK_DEFINITION_ARN=$(echo "$TASK_DEFINITION" | jq -r ".taskDefinition.taskDefinitionArn")
}

function create_new_task_def_json() {
  DEF=$(echo "$TASK_DEFINITION" | jq -r ".taskDefinition.containerDefinitions[].image=\"$image\"" | jq -r ".taskDefinition")

  # Default JQ filter for new task definition
  NEW_DEF_JQ_FILTER="executionRoleArn: .executionRoleArn, family: .family, volumes: .volumes, containerDefinitions: .containerDefinitions, placementConstraints: .placementConstraints"

  # Some options in task definition should only be included in new definition if present in
  # current definition. If found in current definition, append to JQ filter.
  CONDITIONAL_OPTIONS=(networkMode taskRoleArn placementConstraints)
  for i in "${CONDITIONAL_OPTIONS[@]}"; do
    re=".*${i}.*"
    if [[ "$DEF" =~ $re ]]; then
      NEW_DEF_JQ_FILTER="${NEW_DEF_JQ_FILTER}, ${i}: .${i}"
    fi
  done

  # Updated jq filters for AWS Fargate
  REQUIRES_COMPATIBILITIES=$(echo "${DEF}" | jq -r ". | select(.requiresCompatibilities != null) | .requiresCompatibilities[]")
  if [[ "${REQUIRES_COMPATIBILITIES}" == 'FARGATE' ]]; then
    FARGATE_JQ_FILTER='executionRoleArn: .executionRoleArn, requiresCompatibilities: .requiresCompatibilities, cpu: .cpu, memory: .memory'
    NEW_DEF_JQ_FILTER="${NEW_DEF_JQ_FILTER}, ${FARGATE_JQ_FILTER}"
  fi

  # Build new DEF with jq filter
  NEW_DEF=$(echo "$DEF" | jq "{${NEW_DEF_JQ_FILTER}}")

  # If in test mode output $NEW_DEF
  if [ "$BASH_SOURCE" != "$0" ]; then
    echo "$NEW_DEF"
  fi
}

function create_task_def_file() {
  echo "$NEW_DEF" > $TASK_DEF_FILENAME
}

function register_task_def() {
  NEW_TASK_DEFINITION=$(aws ecs register-task-definition --cli-input-json "file://$TASK_DEF_FILENAME")
}

function get_latest_app_spec_info() {
  get_latest_task_definition
  CONTAINER_NAME=$(cat $TASK_DEF_FILENAME | jq '.containerDefinitions[0].name' -r)
  CONTAINER_PORT=$(cat $TASK_DEF_FILENAME  | jq '.containerDefinitions[0].portMappings[0].containerPort' -r)
}

function create_app_spec_file() {
  echo "---
version: 1
Resources:
- TargetService:
    Type: AWS::ECS::Service
    Properties:
      TaskDefinition: <TASK_DEFINITION>
      LoadBalancerInfo:
        ContainerName: ${CONTAINER_NAME}
        ContainerPort: ${CONTAINER_PORT}
" > $APPSPEC_FILENAME
}

function ecs_deploy_service() {
  aws ecs deploy \
          --cluster "$cluster" \
          --service "$service" \
          --task-definition "$TASK_DEF_FILENAME" \
          --codedeploy-appspec "$APPSPEC_FILENAME" \
          --codedeploy-application "$service" \
          --codedeploy-deployment-group "$service"
}

#function waitDeployment() {
#  aws deploy wait deployment-successful --deployment-id d-LKDSY5WVV
#}

function ecs_deploy {
  assert_is_installed "jq"

  local cluster=""
  local service=""
  local image=""
  local iam_role=""
  local from_current_task=""

  while [[ $# > 0 ]]; do
    local key="$1"

    case "$key" in
      --iam-role)
        iam_role="$2"
        shift
        ;;
      --cluster)
        cluster="$2"
        shift
        ;;
      --service)
        service="$2"
        shift
        ;;
      --image)
        image="$2"
        shift
        ;;
      --from-current-task)
        from_current_task="$2"
        shift
        ;;
      --help)
        print_usage
        exit
        ;;
      *)
        echo "ERROR: Unrecognized argument: $key"
        print_usage
        exit 1
        ;;
    esac

    shift
  done

  assert_not_empty "--cluster" "$cluster"
  assert_not_empty "--service" "$service"
  assert_not_empty "--image" "$image"

  # Use specified IAM role or the one which comes from global env variables
  local AWS_ASSUME_ROLE=${iam_role:-${AWS_ROLE_TO_ASSUME_DURING_DEPLOY:-false}}

  #
  local from_current_task=${from_current_task:-false}

  echo "Cluster: $cluster"
  echo "Service: $service"
  echo "Image: $image"
  echo


  if [[ "$AWS_ASSUME_ROLE" != false ]]; then
    echo "Assuming IAM role: $AWS_ASSUME_ROLE"
    assumeRole
    echo "Assumed successfully"
    echo
  fi

  if [[ "$from_current_task" != false ]]; then
    echo "Getting current task definition for the service $service"
    get_current_task_definition
  else
    echo "Getting latest task definition for the service $service"
    get_latest_task_definition
  fi

  echo "Task definition ARN: $TASK_DEFINITION_ARN"
  echo

  echo "Create new task definition"
  create_new_task_def_json
  echo "Created"
  echo

  echo "Create file $TASK_DEF_FILENAME"
  create_task_def_file
  echo "Created"
  echo

  # echo "Register new task definition from file $TASK_DEF_FILENAME"
  # register_task_def
  # echo "Registered"
  # echo
    
  echo "Getting required appspec info from the task definition for the service $service"
  get_latest_app_spec_info
  echo "Task definition ARN: $TASK_DEFINITION_ARN"
  echo

  echo "Create file $APPSPEC_FILENAME"
  create_app_spec_file
  echo "Created"
  echo

  # echo "Deploy ECS service"
  # ecs_deploy_service
  # echo "Done!"


  if [[ "$AWS_ASSUME_ROLE" != false ]]; then
    assumeRoleClean
  fi
}

ecs_deploy "$@"
