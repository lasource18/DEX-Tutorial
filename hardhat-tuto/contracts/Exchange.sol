// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "../node_modules/@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Exchange is ERC20 {
    address public cryptoDevTokenAddress;

    // Exchange is inheriting ERC20, because oir exchange would keep track of Crypto Dev LP tokens
    constructor(address _CryptoDevtoken) ERC20("CryptoDev LP Token", "CDLP") {
        require(_CryptoDevtoken != address(0), "Token address is a null address");
        cryptoDevTokenAddress = _CryptoDevtoken;
    }

    /**
     * @dev Returns the amount of `Crypto Dev Tokens` held by the contract
     */
    function getReserve() public view returns (uint) {
        return ERC20(cryptoDevTokenAddress).balanceOf(address(this));
    }

    /**
     * @dev Adds liquidity to the exchange
     */
    function addLiquidity(uint _amount) public payable returns (uint) {
        uint liquidity;
        uint ethBalance = address(this).balance;
        uint cryptoDevTokenReserve = getReserve();
        ERC20 cryptoDevToken = ERC20(cryptoDevTokenAddress);

        /*
            If the reserve is empty, intake any user supplied value for
            `Ether` and `Crypto Dev` tokens because there is no ratio currently
        */
        if(cryptoDevTokenReserve == 0) {
            // Transfer the `cryptoDevToken` from the user's account to the contract
            cryptoDevToken.transferFrom(msg.sender, address(this), _amount);
            // Take the current ethBalance and mint `ethBalance` amount of LP token to the user.
            // `liquidity` provided is equal to `ethBalance` because this is the first time user
            // is adding `Eth` to the contract, so whatever `Eth` contract has is equak to the one supplied
            // by the user in the current `addLiquidity` call
            // `liquidity` tokens that need to be minted to the user on `addLiquidity` call should always be proportional
            // to the Eth specified by the Eth specified by the user
            liquidity = ethBalance;
            _mint(msg.sender, liquidity);
        } else {
            /*
                If the reserve is not empty, intake any user supplied value for 
                `Ether` and dtermine according ti the ratio how many `Crypto Dev` tokens
                need to be supplied to prevent any large price impacts because of the additional liquidity
            */
            // EthReserve should be the current ethBalance minus the value of ether sent by the user
            // in the current `addLiquidity` call
            uint ethReserve = ethBalance - msg.value;
            // Ratio should always be maintained so there are no major price impacts when adding liquidity
            // Ratio here is -> (cryptoDevTokenAmount user can add/cryptoDevTokenReserve in the contract) = (Eth sent by user/Eth Reserve in the contract)
            // So doing some maths, (cryptoDevTokenAmount user can add) = (Eth sent by user * cryptoDevTokenReserve /Eth Reserve)
            uint cryptoDevTokenAmount = (msg.value * cryptoDevTokenReserve) / ethReserve;
            require(_amount >= cryptoDevTokenAmount, "Amount of token sent is less than the minimum required");
            // transfer only (cryptoDevTokenAmount user can add) amount of `Crypto Dev tokens`
            // to the contract
            cryptoDevToken.transferFrom(msg.sender, address(this), cryptoDevTokenAmount);
            // The amount of LP tokens that would be sent to the user should be proportional to the liquidity of
            // ether added by the user
            // Ratio here to be maintained is ->
            // (LP tokens to be sent to user (liquidity)/ totalSupply of LP tokens in contract) = (Eth sent by the user/ Eth reserve in the contract)
            // doing some maths we get -> liquidity = (totalSupply of LP tokens in contract * Eth sent by user) / (Eth reserve in the contract)
            liquidity = (totalSupply() * msg.value) / ethReserve;
            _mint(msg.sender, liquidity);
        }
        return liquidity;
    }

    /**
     * @dev Returnsthe amount Eth/Crypto Dev tokens that would be returns to the user in the swap
     */
    function removeLiquidity(uint _amount) public returns (uint, uint) {
        require(_amount > 0, "_amount should be greater than zero");
        uint ethReserve = address(this).balance;
        uint _totalSupply = totalSupply();
        // The amountof ETH thst would be sent back to the user is based
        // on a ratio
        // Ratio is -> (ETH sent back to the user) / (current ETH reserve)
        // = (amount of LP tokens that user wants to withdraw) / (total supply of LP tokens)
        // Then by some math -> (ETH sent back to the user)
        // = (current ETH reserve * amount of LP tokens that user wants to withdraw) / (total supply of LP tokens)
        uint ethAmount = (ethReserve * _amount) / _totalSupply;
        // The amount of Crypto Dev token that would be sent back to the user is based
        // on a ratio
        // Ratio is -> (Crypto Dev sent back to the user) / (current Crypto Dev token reserve)
        // = (amount of LP tokens that user wants to withdraw) / (total supply of LP tokens)
        // Then by some math -> (Crypto Dev sent back to the user)
        // = (current Crypto Dev token reserve * amount of LP tokens that user want to withdraw) / (total supply of LP tokens)
        uint cryptoDevTokenAmount = (getReserve() * _amount) / _totalSupply;
        // Burn the sent LP tokens from the user's wallet because they are already sent to
        // remove liquidity
        _burn(msg.sender, _amount);
        // Transfer `ethAmount` of ETH from the contract to the user's wallet
        payable(msg.sender).transfer(ethAmount);
        // Transfer `cryptoDevTokenAmount` of Crypto Dev tokens from the contract to the user's wallet
        ERC20(cryptoDevTokenAddress).transfer(msg.sender, cryptoDevTokenAmount);
        return (ethAmount, cryptoDevTokenAmount);
    }

    /** 
     * @dev Returns the amount ETH/Crypto Dev tokens that would be returned to the user
     * in the swap
     */
     function getAmountOfTokens(uint256 inputAmount, uint256 inputReserve, uint256 outputReserve) public pure returns (uint256) {
        require(inputReserve > 0 && outputReserve > 0, "invalid reserves");
        // We are charging a 1% fee
        // Input amount with fee = (input amount - (1*(input amount)/100)) = ((input amount)*99)/100
        uint256 inputAmountWithFee = inputAmount * 99;
        // Because we need to follow the concept of `XY = K` curve
        // We need to make sure (x + Δx) * (y - Δy) = x * y
        // So the final formula is Δy = (y * Δx) / (x + Δx)
        // Δy in our case is `tokens to be received`
        // Δx = ((input amount)*99)/100, x = inputReserve, y = outputReserve
        // So by putting the values in the formulae you can get the numerator and denominator
        uint256 numerator = inputAmountWithFee * outputReserve;
        uint256 denominator = (inputReserve * 100) + inputAmountWithFee;
        return numerator / denominator;
     }

     /** 
      * @dev Swaps ETH for Cryto Dev tokens
      */
      function ethToCryptoDevToken(uint _minTokens) public payable {
        uint256 tokenReserve = getReserve();
        // call the `getAmountOfTokens` to get the amount of Crypto Dev tokens
        // that would be returned to the user after the swap
        // Notice that the `inputReserve` we are sending in equal to
        // `address(this).balance - msg.value` instead of just `address(this).balance`
        // so we need to substract it to get the actual input reserve
        uint256 tokensBought = getAmountOfTokens(msg.value, address(this).balance, tokenReserve);

        require(tokensBought >= _minTokens, "insufficient output amount");
        // Transfer the Crypto Dev tokens to the user
        ERC20(cryptoDevTokenAddress).transfer(msg.sender, tokensBought);
      }

    /**
     * @dev Swaps Crypto Dev for ETH
     */
    function cryptoDevTokenToEth(uint _tokensSold, uint _minEth) public {
        uint256 tokenReserve = getReserve();
        // call the `getAmountOfTokens` to get the amount of ETH
        // that would be returned to the user after the swap
        uint256 ethBought = getAmountOfTokens(_tokensSold, tokenReserve, address(this).balance);
        require(ethBought >= _minEth, "insufficient output amount");
        // Transfer `Crypto Dev` tokens from the user's address to the contract
        ERC20(cryptoDevTokenAddress).transferFrom(msg.sender, address(this), _tokensSold);
        // send the `ethBought` to the user from the contract
        payable(msg.sender).transfer(ethBought);
    }
}