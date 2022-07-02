FROM node:latest

ENV APP_HOME=/bin/www
WORKDIR $APP_HOME

COPY . $APP_HOME

RUN npm install

ENTRYPOINT ["npm", "start"]
