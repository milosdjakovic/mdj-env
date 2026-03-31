#!/usr/bin/env bash
# Simple preview script for lf
# $1 = file path, $2 = width, $3 = height

case "$(file --mime-type -Lb "$1")" in
  text/*|application/json|application/xml|application/javascript)
    bat --color=always --style=numbers --line-range=:$3 "$1" 2>/dev/null
    ;;
  *)
    file -b "$1"
    ;;
esac
