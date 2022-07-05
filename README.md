# Sample 3tier app
This repo contains code for a Node.js multi-tier application.

The application overview is as follows

```
web <=> api <=> db
```

The folders `web` and `api` respectively describe how to install and run each app.

##  Local testing (using docker compose)
```
docker-compose up --build
```

## Setup
1. Deploy VPC
```
aws cloudformation create-stack --stack-name app-vpc --template-body "file://aws/01-vpc.yaml" --parameters ParameterKey=Env,ParameterValue=prod
```

2. Deploy Infra (lb, ecr, db, etc...)
```
aws cloudformation create-stack --stack-name app-infra --template-body "file://aws/02-infra.yaml" --parameters ParameterKey=NetworkStackName,ParameterValue=app-vpc ParameterKey=DBMasterUser,ParameterValue=appmasteruser ParameterKey=DBMasterPass,ParameterValue=password ParameterKey=DBName,ParameterValue=appdb
```

3. Deploy App Service
```
aws cloudformation create-stack --stack-name poc-ci-cd-apps --template-body "file://aws/03-service.yaml" --parameters ParameterKey=NetworkStackName,ParameterValue=app-vpc ParameterKey=ClusterStackName,ParameterValue=app-infra --capabilities CAPABILITY_IAM
```

4. Deploy Code Pipeline
```
aws cloudformation create-stack --stack-name poc-ci-cd-apps-pipeline --template-body "file://aws/04-ci-cd.yaml" --parameters ParameterKey=ClusterStackName,ParameterValue=poc-ci-cd-infra ParameterKey=ServiceStackName,ParameterValue=poc-ci-ci-apps --capabilities CAPABILITY_IAM
```
