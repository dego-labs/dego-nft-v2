pragma solidity ^0.6.2;

pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "../interface/IERC20.sol";
import "../library/SafeERC20.sol";
import "../library/ReentrancyGuard.sol";

import "../interface/IUniswapV2Router01.sol";
import "../library/UniswapV2Library.sol";

contract NFT1155MarketV2 is ReentrancyGuard {

    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // --- Data ---
    bool private initialized; // Flag of initialize data
    
    address public _governance;

    mapping(address => bool) public _supportCurrency;

    IERC20 public _dandy = IERC20(0x0);
    bool public _isRewardSellerDandy = false;
    bool public _isRewardBuyerDandy = false;
    uint256 public _sellerRewardDandy = 1e15;
    uint256 public _buyerRewardDandy = 1e15;

    struct SalesObject {
        uint256 id;
        uint256 tokenId;
        uint256 unitPrice;
        uint8 status;
        address payable seller;
        IERC1155 nft;
        uint256 amount;
        uint256 initAmount;
        address currency;
        address[] buyers;
    }

    uint256 public _salesAmount = 0;

    SalesObject[] _salesObjects;

    mapping(address => bool) public _supportNft;

    uint256 public _tipsFeeRate = 20;
    uint256 public _baseRate = 1000;
    address payable _tipsFeeWallet;

    event eveSales(
        uint256 indexed id, 
        uint256 tokenId,
        address buyer, 
        uint256 price,
        uint256 tipsFee,
        uint256 sellAmount,
        uint256 surplusAmount
    );

    event eveNewSales(
        uint256 indexed id,
        uint256 tokenId, 
        address seller, 
        address nft,
        address buyer, 
        uint256 unitPrice,
        uint256 amount,
        address currency
    );

    event eveCancelSales(
        uint256 indexed id,
        uint256 tokenId
    );

    event eveNFTReceived(
        address operator, 
        address from, 
        uint256 tokenId, 
        uint256 value,
        bytes data
    );

    event eveSupportCurrency(
        address currency, 
        bool support
    );

    event eveSupportNft(
        address nft,
        bool support
    );

    event GovernanceTransferred(
        address indexed previousOwner, 
        address indexed newOwner
    );

    mapping(address => SupportBuyCurrency) public _supportBuyCurrency;

    uint256 public deflationBaseRate = 100000;

    struct SupportBuyCurrency {
        bool status;
        bool isDeflation;
        uint256 deflationRate;
    }

    IUniswapV2Router01 router = IUniswapV2Router01(0x0);
    
    event eveSupportBuyCurrency(
        address currency, 
        bool status,
        bool isDeflation,
        uint256 deflationRate
    );

    // --- Init ---
    function initialize(
        address payable tipsFeeWallet,
        uint256 minDurationTime,
        uint256 tipsFeeRate,
        uint256 baseRate,
        IERC20 dandy
    ) public {
        require(!initialized, "initialize: Already initialized!");
        _governance = msg.sender;
        _tipsFeeWallet = tipsFeeWallet;
        _tipsFeeRate = tipsFeeRate;
        _baseRate = baseRate;
        _dandy = dandy;
        _isRewardSellerDandy = false;
        _isRewardBuyerDandy = false;
        _sellerRewardDandy = 1e15;
        _buyerRewardDandy = 1e15;
        initReentrancyStatus();
        initialized = true;
    }

    modifier onlyGovernance {
        require(msg.sender == _governance, "not governance");
        _;
    }

    function setGovernance(address governance)  public  onlyGovernance
    {
        require(governance != address(0), "new governance the zero address");
        emit GovernanceTransferred(_governance, governance);
        _governance = governance;
    }


    /**
     * check address
     */
    modifier validAddress( address addr ) {
        require(addr != address(0x0));
        _;
    }

    modifier checkindex(uint index) {
        require(index <= _salesObjects.length, "overflow");
        _;
    }

    modifier checkSupportBuyCurrendy(address currency) {
        SupportBuyCurrency memory supportBuyCurrency = _supportBuyCurrency[currency];
        require(supportBuyCurrency.status == true, "not support currency");
        _;
    }

    modifier mustNotSellingOut(uint index) {
        require(index <= _salesObjects.length, "overflow");
        SalesObject storage obj = _salesObjects[index];
        require(obj.status == 0, "sry, selling out");
        _;
    }

    modifier onlySalesOwner(uint index) {
        require(index <= _salesObjects.length, "overflow");
        SalesObject storage obj = _salesObjects[index];
        require(obj.seller == msg.sender || msg.sender == _governance, "author & governance");
        _;
    }

    function seize(IERC20 asset) external onlyGovernance returns (uint256 balance) {
        balance = asset.balanceOf(address(this));
        asset.safeTransfer(_governance, balance);
    }

    function setIUniswapV2Router01(IUniswapV2Router01 router_) public onlyGovernance {
        router = router_;
    }


    function addSupportNft(address nft) public onlyGovernance validAddress(nft) {
        _supportNft[nft] = true;
        emit eveSupportNft(nft, true);
    }

    function removeSupportNft(address nft) public onlyGovernance validAddress(nft) {
        _supportNft[nft] = false;
        emit eveSupportNft(nft, false);
    }

    function addSupportCurrency(address erc20) public onlyGovernance {
        require(_supportCurrency[erc20] == false, "the currency have support");
        _supportCurrency[erc20] = true;
        emit eveSupportCurrency(erc20, true);
    }

    function removeSupportCurrency(address erc20) public onlyGovernance {
        require(_supportCurrency[erc20], "the currency can not remove");
        _supportCurrency[erc20] = false;
        emit eveSupportCurrency(erc20, false);
    }

    function setSupportBuyCurrency(address erc20,bool status,bool isDeflation,uint256 deflationRate ) public onlyGovernance {
        _supportBuyCurrency[erc20] = SupportBuyCurrency(status,isDeflation,deflationRate);
        emit eveSupportBuyCurrency(erc20,status,isDeflation,deflationRate);
    }

    function setTipsFeeWallet(address payable wallet) public onlyGovernance {
        _tipsFeeWallet = wallet;
    }

    function getSales(uint index) external view checkindex(index) returns(SalesObject memory) {
        return _salesObjects[index];
    }

    function getSalesBuyers(uint index) external view checkindex(index) returns(address[] memory) {
        SalesObject memory obj = _salesObjects[index];
        address[] memory saleBuyers = new address[](obj.buyers.length);
        saleBuyers = obj.buyers;
        return saleBuyers;
    }

    function getSalesPrice(uint index)
        external
        view
        checkindex(index)
        returns (uint256)
    {
        SalesObject storage obj = _salesObjects[index];
        return obj.unitPrice;
    }

    function setBaseRate(uint256 rate) external onlyGovernance {
        _baseRate = rate;
    }

    function setTipsFeeRate(uint256 rate) external onlyGovernance {
        _tipsFeeRate = rate;
    }

    
    function cancelSales(uint index) external checkindex(index) onlySalesOwner(index) mustNotSellingOut(index) nonReentrant {
        SalesObject storage obj = _salesObjects[index];
        obj.status = 2;
        obj.nft.safeTransferFrom(address(this), obj.seller, obj.tokenId, obj.amount, "");

        emit eveCancelSales(index, obj.tokenId);
    }

    function startSales(uint256 _tokenId,
                        uint256 _unitPrice,
                        address _nft,
                        uint256 _amount,
                        address _currency)
        external 
        nonReentrant
        validAddress(_nft)
        returns(uint)
    {
        uint256 tokenId = _tokenId;
        uint256 unitPrice = _unitPrice;
        address nft = _nft;
        uint256 amount = _amount;
        address currency = _currency;
        require(tokenId != 0, "invalid token");
        require(unitPrice >= 0, "invalid price");
        require(_supportNft[nft] == true, "cannot sales");
        require(_supportCurrency[currency] == true, "not support currency");

        IERC1155(nft).safeTransferFrom(msg.sender, address(this), tokenId, amount, "");

        _salesAmount++;
        SalesObject memory obj;

        obj.id = _salesAmount;
        obj.tokenId = tokenId;
        obj.seller = msg.sender;
        obj.nft = IERC1155(nft);
        obj.unitPrice = unitPrice;
        obj.status = 0;
        obj.amount = amount;
        obj.initAmount = obj.amount;
        obj.currency = currency;
        
        if (_salesObjects.length == 0) {
            SalesObject memory zeroObj;
            zeroObj.tokenId = 0;
            zeroObj.seller = address(0x0);
            zeroObj.nft = IERC1155(0x0);
            zeroObj.unitPrice = unitPrice;
            zeroObj.status = 2;
            zeroObj.amount = 0;
            zeroObj.currency = address(0x0);
            _salesObjects.push(zeroObj);    
        }

        _salesObjects.push(obj);

        if(_isRewardSellerDandy) {
            _dandy.mint(msg.sender, _sellerRewardDandy);
        }

        emit eveNewSales(
            obj.id, 
            tokenId, 
            msg.sender, 
            nft, 
            address(0x0), 
            unitPrice,
            amount,
            currency
        );
        return _salesAmount;
    }

    function buy(uint index,uint256 _amount, address currency_)
        public
        nonReentrant
        mustNotSellingOut(index)
        checkSupportBuyCurrendy(currency_)
        payable 
    {
        uint256 amount = _amount;
        SalesObject storage obj = _salesObjects[index];
        require (obj.amount >= amount, "umm.....  It's too much");
        uint256 unitPrice = this.getSalesPrice(index);
        uint256 price = unitPrice * amount;
        uint256 tipsFee = price.mul(_tipsFeeRate).div(_baseRate);
        uint256 purchase = price.sub(tipsFee);
        if (obj.currency == currency_){
            if (obj.currency == address(0x0)) { 
                require (msg.value >= this.getSalesPrice(index), "umm.....  your price is too low");
                uint256 returnBack = msg.value.sub(price);
                if(returnBack > 0) {
                    msg.sender.transfer(returnBack);
                }
                if(tipsFee > 0) {
                    _tipsFeeWallet.transfer(tipsFee);
                }
                obj.seller.transfer(purchase);
            } else {
                IERC20(obj.currency).safeTransferFrom(msg.sender, _tipsFeeWallet, tipsFee);
                IERC20(obj.currency).safeTransferFrom(msg.sender, obj.seller, purchase);
            }
        }else{
            if (obj.currency == address(0x0)){
                // uint256 ethAmount = 0;
                // SupportBuyCurrency memory supportBuyCurrency = _supportBuyCurrency[currency_];
                // if (supportBuyCurrency.isDeflation) {
                //     ethAmount = exactTokenToEth(currency_, price);
                // } else {
                //     ethAmount = tokenToExactEth(currency_, price);
                // }
                uint256 ethAmount = tokenToEth(currency_, price);
                require (ethAmount >= price, "umm.....  your price is too low");
                uint256 returnBack = ethAmount.sub(price).add(msg.value);
                if(returnBack > 0) {
                    msg.sender.transfer(returnBack);
                }
                if(tipsFee > 0) {
                    _tipsFeeWallet.transfer(tipsFee);
                }
                obj.seller.transfer(purchase);
            }else{
                // transfer
                require(false, "not support token");
            }
        }
        
        
        obj.nft.safeTransferFrom(address(this), msg.sender, obj.tokenId, amount, "");
        
        obj.buyers.push(msg.sender);
        obj.amount = obj.amount.sub(amount);

        if (obj.amount == 0) {
            obj.status = 1;    
        }

        if(_isRewardBuyerDandy) {
            _dandy.mint(msg.sender, _buyerRewardDandy);
        }
        // fire event
        emit eveSales(
            index, 
            obj.tokenId, 
            msg.sender, 
            price, 
            tipsFee, 
            amount, 
            obj.amount
        );
    }
    function setDandyAddress(address addr) external onlyGovernance validAddress(addr) {
        _dandy = IERC20(addr);
    }

    function setSellerRewardDandy(uint256 rewardDandy) public onlyGovernance {
        _sellerRewardDandy = rewardDandy;
    }

    function setBuyerRewardDandy(uint256 rewardDandy) public onlyGovernance {
        _buyerRewardDandy = rewardDandy;
    }

    function setIsRewardSellerDandy(bool isRewardSellerDandy) public onlyGovernance {
        _isRewardSellerDandy = isRewardSellerDandy;
    }

    function setIsRewardBuyerDandy(bool isRewardBuyerDandy) public onlyGovernance {
        _isRewardBuyerDandy = isRewardBuyerDandy;
    }


    function onERC1155Received(address operator, address from, uint256 tokenId, uint256 value, bytes calldata data) external returns (bytes4) {
        //only receive the _nft staff
        if(address(this) != operator) {
            //invalid from nft
            return 0;
        }

        //success
        emit eveNFTReceived(operator, from, tokenId, value, data);
        return bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"));
    }

    // function exactTokenToEth(address erc20Token_, uint256 amountOutMin) internal returns (uint256) {
    //     address erc20Token = erc20Token_;
    //     SupportBuyCurrency memory supportBuyCurrency = _supportBuyCurrency[erc20Token];

    //     address[] memory path = new address[](2);
    //     path[0] = erc20Token;
    //     path[1] = router.WETH();

    //     uint256[] memory amounts = UniswapV2Library.getAmountsIn(router.factory(), amountOutMin, path);
    //     uint256 amountInMax = amounts[0];
        
    //     uint256 amountIn = amountInMax.mul(deflationBaseRate).div(supportBuyCurrency.deflationRate).mul(deflationBaseRate).div(supportBuyCurrency.deflationRate);
    //     uint256 balanceBefore = IERC20(erc20Token).balanceOf(address(this));
    //     IERC20(erc20Token).safeTransferFrom(msg.sender, address(this), amountIn);
    //     uint256 balanceAfter = IERC20(erc20Token).balanceOf(address(this));
    //     amountIn = balanceAfter.sub(balanceBefore);
    //     IERC20(erc20Token).approve(address(router), amountIn);

    //     uint256 ethBefore = address(this).balance;
    //     // router.swapExactTokensForETH(amountIn, amountOutMin, path, address(this), block.timestamp);
    //     router.swapExactTokensForETHSupportingFeeOnTransferTokens(amountIn, 0, path, address(this), block.timestamp);
    //     uint256 ethAfter = address(this).balance;

    //     uint256 balanceLast = IERC20(erc20Token).balanceOf(address(this));
    //     uint256 supAmount = balanceLast.sub(balanceBefore);
    //     if (supAmount>0){
    //         IERC20(erc20Token).safeTransfer(msg.sender, supAmount);
    //     }

    //     return ethAfter.sub(ethBefore);
    // }

    // function tokenToExactEth(address erc20Token, uint256 amountOut) internal returns (uint256) {
    //     address[] memory path = new address[](2);
    //     path[0] = erc20Token;
    //     path[1] = router.WETH();
       
    //     uint256[] memory amounts = UniswapV2Library.getAmountsIn(router.factory(), amountOut, path);
    //     uint256 amountInMax = amounts[0];
        
    //     uint256 balanceBefore = IERC20(erc20Token).balanceOf(address(this));
    //     IERC20(erc20Token).safeTransferFrom(msg.sender, address(this), amountInMax);
    //     uint256 balanceAfter = IERC20(erc20Token).balanceOf(address(this));
    //     amountInMax = balanceAfter.sub(balanceBefore);
    //     IERC20(erc20Token).approve(address(router), amountInMax);

    //     uint256 ethBefore = address(this).balance;
    //     router.swapTokensForExactETH(amountOut, amountInMax, path, address(this), block.timestamp);
    //     uint256 ethAfter = address(this).balance;

    //     uint256 balanceLast = IERC20(erc20Token).balanceOf(address(this));
    //     uint256 supAmount = balanceLast.sub(balanceBefore);
    //     if (supAmount>0){
    //         IERC20(erc20Token).safeTransfer(msg.sender, supAmount);
    //     }
    //     return ethAfter.sub(ethBefore);
    // }

    function tokenToEth(address erc20Token, uint256 amountOut) private returns(uint256) {
        address[] memory path = new address[](2);
        path[0] = erc20Token;
        path[1] = router.WETH();
       
        uint256[] memory amounts = UniswapV2Library.getAmountsIn(router.factory(), amountOut, path);
        uint256 amountIn = amounts[0];
        
        SupportBuyCurrency memory supportBuyCurrency = _supportBuyCurrency[erc20Token];
        if (supportBuyCurrency.isDeflation) {
            amountIn = amountIn.mul(deflationBaseRate).div(supportBuyCurrency.deflationRate).mul(deflationBaseRate).div(supportBuyCurrency.deflationRate);
        }

        uint256 balanceBefore = IERC20(erc20Token).balanceOf(address(this));
        IERC20(erc20Token).safeTransferFrom(msg.sender, address(this), amountIn);
        uint256 balanceAfter = IERC20(erc20Token).balanceOf(address(this));
        amountIn = balanceAfter.sub(balanceBefore);
        IERC20(erc20Token).approve(address(router), amountIn);
        
        uint256 ethBefore = address(this).balance;
        if (supportBuyCurrency.isDeflation) {
            router.swapExactTokensForETHSupportingFeeOnTransferTokens(amountIn, 0, path, address(this), block.timestamp);
        } else {
            router.swapTokensForExactETH(amountOut, amountIn, path, address(this), block.timestamp);
        }
        uint256 ethAfter = address(this).balance;

        uint256 balanceLast = IERC20(erc20Token).balanceOf(address(this));
        uint256 supAmount = balanceLast.sub(balanceBefore);
        if (supAmount>0){
            IERC20(erc20Token).safeTransfer(msg.sender, supAmount);
        }
        return ethAfter.sub(ethBefore);
    }
}
