#!/bin/sh

if [ ! $CI ]; then
  export PATH=$PATH:/opt/homebrew/bin
  swift format --configuration .swift-format -r ./Sources -i
  swift format --configuration .swift-format -r ./Package.swift -i
fi
