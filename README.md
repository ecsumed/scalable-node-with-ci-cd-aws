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
aws cloudformation create-stack --stack-name 3-tier-node --template-body "file://aws/01-vpc.yaml" --parameters ParameterKey=Env,ParameterValue=prod
```

2. Deploy Infra (lb, db, etc...)
```
```

3. Deploy App
```
```
