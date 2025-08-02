#!/bin/bash

n=2000
while true; do
  n=$((n+1))
  echo "$n!"
  curl "http://localhost/factorial/$n?key=abcd-1234-5678"
  echo
done