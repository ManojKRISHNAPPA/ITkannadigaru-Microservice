# 1) Base image with Node installed
#Choose the runtime (Node 20 on Alpine Linux → small, secure, fast)
FROM node:20-alpine

# 2) Work directory inside container
# Set working directory inside container
WORKDIR /app

# 3) Copy only package files first (best practice for caching)
# Copy dependency manifest first (for Docker layer caching)
COPY package*.json ./

# 4) Install dependencies (reproducible)
# Install dependencies in a repeatable production way
# npm ci → uses package-lock.json exactly (reproducible builds)
# --omit=dev → installs only production dependencies (smaller image)
RUN npm ci --omit=dev

# 5) Copy the application code
# Copy application source code
COPY src ./src

# 6) App runs on 8080 inside container
# Document which port the container is expected to run on
# (Note: this does NOT open firewall ports)
ENV PORT=8080
EXPOSE 8080

# 7) Start the service
# Default command when container starts
CMD ["npm", "start"]

#------------------------------
#A Docker image is like a packed box containing:
#a mini filesystem
#your app code
#your dependencies (node_modules)
#instructions on how to start the app (CMD ...)

#------------------------------
#Why immutable matters in real companies
#------------------------------
#If prod breaks, we must be able to answer:
#What exact thing was deployed?
#Can we redeploy the same thing?
#Can we rollback to the previous thing?
#Docker image tags help us do this.


