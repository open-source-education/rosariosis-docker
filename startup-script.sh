#!/bin/bash

source /etc/apache2/envvars

echo " [info] Start the apache2 server in foreground."
apache2 -DFOREGROUND
