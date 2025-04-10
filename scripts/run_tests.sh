#!/bin/bash

# Run the Rust parser testing script
echo "Test anltr installed correctly and Rust parser works"
python3 parser/testing_script.py

echo "Test our parser works"
python3 parser/test_gen_parse_tree.py
