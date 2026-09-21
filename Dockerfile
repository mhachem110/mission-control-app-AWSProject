# Package the exact site that GitHub Actions will test and deploy.
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 80
