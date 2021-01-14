echo "deploy begin....."

TF_CMD=node_modules/.bin/truffle-flattener

echo "" >  ./deployments/NFT1155Market.full.sol
cat  ./scripts/head.sol >  ./deployments/NFT1155Market.full.sol
$TF_CMD ./contracts/market/NFT1155Market.sol >>  ./deployments/NFT1155Market.full.sol 


# echo "" >  ./deployments/NFT1155MarketProxy.full.sol
# cat  ./scripts/head.sol >  ./deployments/NFT1155MarketProxy.full.sol
# $TF_CMD ./contracts/market/NFT1155MarketProxy.sol >>  ./deployments/NFT1155MarketProxy.full.sol 


echo "" >  ./deployments/NFT1155MarketV2.full.sol
cat  ./scripts/head.sol >  ./deployments/NFT1155MarketV2.full.sol
$TF_CMD ./contracts/market/NFT1155MarketV2.sol >>  ./deployments/NFT1155MarketV2.full.sol 

# rm *_sol_*

echo "deploy end....."