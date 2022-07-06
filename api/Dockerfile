FROM 874439048424.dkr.ecr.us-east-1.amazonaws.com/node:latest

ENV APP_HOME=/bin/www
WORKDIR $APP_HOME

COPY . $APP_HOME

RUN npm install

ENTRYPOINT ["npm", "start"]
