FROM public.ecr.aws/nginx/nginx:latest
COPY app1/index.html /usr/share/nginx/html/index.html