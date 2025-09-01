#!/bin/sh

JSON_RPC_BASE="https://evm-testnet.chainweb.com/chainweb/0.0/evm-testnet"

# extract the variables we need from json output
ONE_TIME_SIGNER_ADDRESS="0x$(cat output/deployment.json | jq --raw-output '.signerAddress')"
GAS_COST="0x$(printf '%x' $(($(cat output/deployment.json | jq --raw-output '.gasPrice') * $(cat output/deployment.json | jq --raw-output '.gasLimit'))))"
TRANSACTION="0x$(cat output/deployment.json | jq --raw-output '.transaction')"
DEPLOYER_ADDRESS="0x$(cat output/deployment.json | jq --raw-output '.address')"
BYTECODE="0x$(cat output/deployment.json | jq --raw-output '.deploymentBytecode')"

echo "Deploying create2proxy:\n$DEPLOYER_ADDRESS"

for i in {20..24}; do
	JSON_RPC="$JSON_RPC_BASE/chain/$i/evm/rpc"

	echo "\nChain $i:\n---------------------"

	code=$(curl -s -X POST "$JSON_RPC" \
		-H "Content-Type: application/json" \
		-d "{
    \"jsonrpc\":\"2.0\",
    \"method\":\"eth_getCode\",
    \"params\":[\"$DEPLOYER_ADDRESS\", \"latest\"],
    \"id\":1
  }" | jq -r '.result')

	if [[ "$code" != "0x" && "$BYTECODE" == *"${code#0x}"* ]]; then
		echo "✅ Already deployed"
		continue
	fi

	if [ "$code" != "0x" ]; then
		echo "❌ contract code mismatch"
		continue
	fi

	BALANCE_HEX=$(curl -s -X POST ${JSON_RPC} \
		-H "Content-Type: application/json" \
		--data "{
    \"jsonrpc\":\"2.0\",
    \"method\":\"eth_getBalance\",
    \"params\":[\"$ONE_TIME_SIGNER_ADDRESS\", \"latest\"],
    \"id\":1
  }" | jq -r '.result')

	# if null or empty → account not found
	if [ -z "$BALANCE_HEX" ] || [ "$BALANCE_HEX" == "null" ]; then
		echo "❌ Error: account $ONE_TIME_SIGNER_ADDRESS not found on chain $i"
		exit 1
	fi

	# convert to decimal
	BALANCE_DEC=$(printf "%d" "$BALANCE_HEX")
	GAS_COST_DEC=$(printf "%d" "$GAS_COST")

	if [ "$BALANCE_DEC" -lt "$GAS_COST_DEC" ]; then
		echo "❌ Error: insufficient balance for $ONE_TIME_SIGNER_ADDRESS (have $BALANCE_DEC, need $GAS_COST_DEC)"
		exit 1
	fi

	# deploy the deployer contract
	curl $JSON_RPC -X 'POST' -H 'Content-Type: application/json' --data "{\"jsonrpc\":\"2.0\", \"id\":1, \"method\": \"eth_sendRawTransaction\", \"params\": [\"$TRANSACTION\"]}"
	echo "\n⛏️ deploying... waiting for transaction to be mined"
done
