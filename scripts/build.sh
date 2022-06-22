#!/bin/bash

LIGO_VERSION=0.44.0
BUILD_DIRECTORY=./build
BUILD_MICHELSON_DIRECTORY=$BUILD_DIRECTORY/michelson
BUILD_JSON_DIRECTORY=$BUILD_DIRECTORY/json
CONTRACTS_DIRECTORY=./src

if [[ "$OSTYPE" == "msys"* ]]; then
    ligo="docker run --rm -v /\"\$PWD\":\"\$PWD\" -w /\"\$PWD\" ligolang/ligo:$LIGO_VERSION"
else
    ligo="docker run --rm -v \"\$PWD\":\"\$PWD\" -w \"\$PWD\" ligolang/ligo:$LIGO_VERSION"
fi

rm -rf $BUILD_DIRECTORY
mkdir -p $BUILD_MICHELSON_DIRECTORY $BUILD_JSON_DIRECTORY

# $1: a contract file name without extension
compile_contract() {
    echo "Compile contract: $1"
    eval "$ligo compile contract --michelson-format text --output-file $BUILD_MICHELSON_DIRECTORY/$1.tz \
        $CONTRACTS_DIRECTORY/$1.ligo"
    eval "$ligo compile contract --michelson-format json --output-file $BUILD_JSON_DIRECTORY/$1.json \
        $CONTRACTS_DIRECTORY/$1.ligo"
}

# Contracts
compile_contract atomex $@
