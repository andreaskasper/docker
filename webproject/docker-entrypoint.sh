#!/bin/bash

service ssh start
service mysql start
/usr/sbin/nginx -g "daemon off;"
