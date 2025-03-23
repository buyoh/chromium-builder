#!/bin/bash

set -eu

cd $(dirname $0)

INPUT_TAG=$1

if [[ -z "$INPUT_TAG" ]]; then
    echo ''
    exit 0
fi

for tag in $(cat ./checkout_list.txt); do
    if [[ "$tag" == "#"* ]]; then
        continue
    fi
    # TODO: Care about '11.' and '110.'
    if [[ "$tag" == "$INPUT_TAG"* ]]; then
        echo $tag
        exit 0
    fi
done

echo ''
