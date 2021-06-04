FROM node:12

# Create app directory
WORKDIR .

# Install app dependencies
# A wildcard is used to ensure that both package.json and package-lock.json are copied
COPY package*.json ./

RUN npm install
# If you're building your code for production use
# RUN npm ci - only=production

# Bundle into docker image
COPY . .

EXPOSE 8000

# CMD ["node", "index.js"]
