// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.3;
// suplies owner functionality (standart remix example)
import "./contracts/2_Owner.sol";
// supplies Safe Math and standart BEP20 Token 
import "./BEP20Token.sol";

//-----------------------------------------
// the contract is in development , feedback is appreciated 

/**
 * @dev crowd sale contract with fund and coin timelock and refund option
 *
 * State overview:
 * 1) construction, transfer token to contract, activation of crowd sale ( requires tokens for sale <= tokens locked in contract )
 * 2) buy token ( send BNB to contract. buy/receive) -> balance of address will increase AND funds stay in contract 
 * 3) Withdraw token ( after token time lock opens ) -> contract sends token to address AND sets address balance to zero AND increases address withdraw amount by amount
 * 4) return token ( if active ) after min hold period -> send BNB to address AND set address withdraw amount to zero
 * 5) destroy ( after fundLock opens) send funds to _vault and destruct contract (if all tokens are withdrawn)
 * 
 * The contract is not optimised for gas cost in any way, feel free to open issues of or fix it yourself (please keep the GLP-3 license in mind and publish your improvements)
 * 
 */



contract CrowdSaleAdvanced is Owner {
    using SafeMath for uint256;
    
    string public name;
    
    // The amount of token a address has bought but not withdrawn
    mapping (address => uint256) private _balances;
    
     // The amount of token a address has withdrawn and not given back
    mapping (address => uint256) private _withdrawn;
    
    
    
   
    address private _tokenContract;
    address payable private _vault;
    
    // the token for sale ( Interface has to be known while compiling)
    BEP20Token private  Token;
    
    
   
    uint256 public minimumBuy; // in BNB 
    uint256 public maximumBuy;
    // the contract does not track if one address buys token multiple times 
    
    uint256 public saleMultiplier; // tokens per BNB
    
    // total amount of tokens for sale ( has to be smaller thant the token balance of the contrakt for the sale to be activated)
    uint256 private tokensForSale;
    

    uint256 private tokensSold;
    uint256 private tokensWithdrawn;
    uint256 public refundPercentage; 
    
    // unix timestamp : time when tokens can be withdrawn 
    uint256 public tokenLock;
    // unix timestamp : time when BNB can be withdrawn to _vault
    uint256 public fundLock;
    

    

    event Buy(address buyer , uint256 value , uint256 amount);
    event Withdraw(address buyer, uint amount);
    

    
    constructor() {
        // example values 
        minimumBuy = 1 ;
        maximumBuy = 10000000000000000000;
        saleMultiplier = 9000;
        tokensForSale = 10000000000000000000000000;
        refundPercentage = 80;
        name = "name";
        _vault = payable(0xdD870fA1b7C4700F2BD7f44238821C26f7392148);
        _tokenContract = 0xd8b934580fcE35a11B58C6D73aDeE468a2833fa8;
        
        Token = BEP20Token(_tokenContract);
    }
    
    


    function tokenContract() external view returns(address){
        return _tokenContract;
    }
    

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }
    
    // -----------------------------------------
    // Crowdsale main function external 
    // -----------------------------------------
    
    function buy(address buyer) external payable {
        _buy(buyer,msg.value);
        
    }
    
    
    function _buy(address buyer, uint256 value) internal {
        
        uint256 amount = value.mul(saleMultiplier);
        uint256 tokensSold_local = tokensSold.add(amount);
         
        require(msg.value >= minimumBuy, "BNB mount to small");
        require(msg.value <= maximumBuy, "BNB amount to large");
        require(tokensSold_local <= tokensForSale);
         
         _balances[buyer] = _balances[buyer].add(amount);
         tokensSold = tokensSold_local;
         
         emit Buy(buyer,value, amount);
         
    }

    
    
  
    function withdrawToken() external {
        
         // define local balace to prevent Re-Entrancy
        uint256 local_balance = _balances[msg.sender] ;
        
        // set balance to zero 
        _balances[msg.sender] = 0;
        
        // check if timelock is still active 
        require(tokenLock < block.timestamp, "Timelock is active.");
        
        // require the address to hold locked tokens 
        require(local_balance > 0 , "The balance for this account is zero");
        
        // transfer tokens to address
        require(Token.transfer(msg.sender,local_balance ));
        
        // add withdrawn tokens amount to total withdrwan amount
        tokensWithdrawn = tokensWithdrawn.add( local_balance);
        
        // add amount to address withdrawn tokens
        _withdrawn[msg.sender] =   local_balance;
        
        // emit event with amount of tokens 
        emit Withdraw(msg.sender, local_balance);
        

    } 
    
    // refund bought tokens , requires allowance for for contract to equalt the returnd amount 
    function refund(uint256 amount, address payable receiver) external {
        
        // refund must happen before fundlock opens 
        require(fundLock > block.timestamp, "Return period is over.");
        
        // require msg.sender to own withdrawn tokens to return
        // decrease address _withdrawn balance 
        _withdrawn[msg.sender] = _withdrawn[msg.sender].sub(amount,"You cant refund this amount of tokens.");
        
        // require transfer from msg.sender to contract to be succesfull 
        require(Token.transferFrom(msg.sender,address(this),amount), "The granted allowance is to small.");
        
        // calculate BNB value for token amount : value = {amount / saleMultiplier = BNB value}  * refund rate ( 0 < refund rate < 1) 
        uint256 _value = amount.div(saleMultiplier).mul(refundPercentage).div(100);
        
        // send BNB value to receiver
        receiver.call{value: _value};
        
    }
    
        // withdraw BNB after fund timelock opens 
    function withdrawFunds(uint256 gas) external view isOwner {
        
        // require vault to be valid and timelock to be open 
         //require(_vault != address(0) , "The vault address is zero");
         require(fundLock < block.timestamp, "Timelock is active.");
         
         // send BNB to _vault ( gas variable to ensure funds are retreavable )
         _vault.call{gas: gas, value: address(this).balance};
    }
    
    
    // destruct contract 
    function destruct() external isOwner {
        // require vault to be valid AND funds timelock to be open AND all tokens to be withdrawn 
        
        //require(_vault != address(0) , "The vault address is zero");##############
        require(fundLock < block.timestamp, "Timelock is active.");
        require(tokensWithdrawn == tokensSold , "Token withdraw not done");
        
        //require(_tokenContract != address(0) ); #######################
        
        // If not all tokens have been sold transfer them back to owner 
        if( Token.balanceOf(address(this)) > 0 ) {
            require(Token.transfer( _owner(), Token.balanceOf(address(this)) ));
        }
        
        // destroct contract send funds to _vault 
        selfdestruct(_vault);  
        
    }
    
    // fallback functions will buy tokens for sender 
    fallback () external  payable {
        _buy(msg.sender,msg.value);
    }
   
    receive() external payable { 
        _buy(msg.sender,msg.value); 
        
    }
    
}
