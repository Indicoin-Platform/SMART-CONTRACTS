pragma solidity ^0.4.10;

/* taking ideas from FirstBlood token */
contract SafeMath {

    /* function assert(bool assertion) internal { */
    /*   if (!assertion) { */
    /*     throw; */
    /*   } */
    /* }      // assert no longer needed once solidity is on 0.4.10 */

    function safeAdd(uint256 x, uint256 y) internal returns(uint256) {
      uint256 z = x + y;
      assert((z >= x) && (z >= y));
      return z;
    }

    function safeSubtract(uint256 x, uint256 y) internal returns(uint256) {
      assert(x >= y);
      uint256 z = x - y;
      return z;
    }

    function safeMult(uint256 x, uint256 y) internal returns(uint256) {
      uint256 z = x * y;
      assert((x == 0)||(z/x == y));
      return z;
    }

}


contract Token {
    uint256 public totalSupply;
    function balanceOf(address _owner) constant returns (uint256 balance);
    function transfer(address _to, uint256 _value) returns (bool success);
    function transferFrom(address _from, address _to, uint256 _value) returns (bool success);
    function approve(address _spender, uint256 _value) returns (bool success);
    function allowance(address _owner, address _spender) constant returns (uint256 remaining);
    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
}


/*  ERC 20 token */
contract StandardToken is Token {

    function transfer(address _to, uint256 _value) returns (bool success) {
      if (balances[msg.sender] >= _value && _value > 0) {
        balances[msg.sender] -= _value;
        balances[_to] += _value;
        Transfer(msg.sender, _to, _value);
        return true;
      } else {
        return false;
      }
    }

    function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {
      if (balances[_from] >= _value && allowed[_from][msg.sender] >= _value && _value > 0) {
        balances[_to] += _value;
        balances[_from] -= _value;
        allowed[_from][msg.sender] -= _value;
        Transfer(_from, _to, _value);
        return true;
      } else {
        return false;
      }
    }

    function balanceOf(address _owner) constant returns (uint256 balance) {
        return balances[_owner];
    }

    function approve(address _spender, uint256 _value) returns (bool success) {
        allowed[msg.sender][_spender] = _value;
        Approval(msg.sender, _spender, _value);
        return true;
    }

    function allowance(address _owner, address _spender) constant returns (uint256 remaining) {
      return allowed[_owner][_spender];
    }

    mapping (address => uint256) balances;
    mapping (address => mapping (address => uint256)) allowed;
}
contract Indicoin is StandardToken, SafeMath {

    // metadata
    string public constant name = "Indicoin";
    string public constant symbol = "INDI";
    uint256 public constant decimals = 18;
    string public version = "1.0";

    // contracts
    address public ethFundDeposit;      // deposit address for ETH for Indicoin Developers
    address public indiFundDeposit;      // deposit address for indicoin developrs use, social vault and bounty
    address public socialVaultNteamDeposit; // deposit address for SocialVault
    address public bountyDeposit; // deposit address for bounty
    address public preSaleDeposit; //deposit address for preSale
    // crowdsale parameters
    bool public isFinalized;              // switched to true in operational state
    uint256 public fundingStartBlock;
    uint256 public fundingEndBlock;
    uint256 public constant socialVaultNteam = 550 * (10**6) * 10**decimals; // 450m INDI reserved for social vault + 100m for indicoin team
    uint256 public constant bounty = 50 * (10**6) * 10**decimals; // 50m INDI reserved for bounty
    uint256 public constant preSale = 20 * (10**6) * 10**decimals; // 20m INDI reserved for preSale manual distribution
    uint256 public constant tokenExchangeRate = 12500; // 12500 INDI tokens per 1 ETH
    uint256 public constant tokenCreationCap =  1000 * (10**6) * 10**decimals;
    uint256 public constant tokenCreationMin =  632 * (10**6) * 10**decimals;


    // events
    event LogRefund(address indexed _to, uint256 _value);
    event CreateINDI(address indexed _to, uint256 _value);
    
    
    // constructor
    function Indicoin(
        address _ethFundDeposit,
        address _socialVaultNteamDeposit,
        address _bountyDeposit,
        address _preSaleDeposit,
        uint256 _fundingStartBlock,
        uint256 _fundingEndBlock)
    {
      isFinalized = false;                   //controls pre through crowdsale state
      ethFundDeposit = _ethFundDeposit;
      preSaleDeposit = _preSaleDeposit;
      socialVaultNteamDeposit = _socialVaultNteamDeposit;
      bountyDeposit = _bountyDeposit;
      fundingStartBlock = _fundingStartBlock;
      fundingEndBlock = _fundingEndBlock;
      
      totalSupply = socialVaultNteam + bounty + preSale;
      balances[socialVaultNteamDeposit] = socialVaultNteam; // Deposit Social vault Share
      balances[bountyDeposit] = bounty; //Deposit bounty Share
      balances[preSaleDeposit] = preSale; //Deposit preSale Share
      CreateINDI(socialVaultNteamDeposit, socialVaultNteam); // logs socialVault fund
      CreateINDI(bountyDeposit, bounty); // logs bounty fund
      CreateINDI(preSaleDeposit, preSale); // logs preSale fund
    }
    
    /// @dev Accepts ether and creates new INDI tokens.
    function createTokens() payable external {
      if (isFinalized) revert();
      if (block.number < fundingStartBlock) revert();
      if (block.number > fundingEndBlock) revert();
      if (msg.value == 0) revert();

      uint256 tokens = safeMult(msg.value, tokenExchangeRate); // check that we're not over totals
      uint256 checkedSupply = safeAdd(totalSupply, tokens);

      // return money if something goes wrong
      if (tokenCreationCap < checkedSupply) revert();  // odd fractions won't be found

      totalSupply = checkedSupply;
      balances[msg.sender] += tokens;  // safeAdd not needed; bad semantics to use here
      CreateINDI(msg.sender, tokens);  // logs token creation
    }
    
    
    /// @dev Ends the funding period and sends the ETH home
    function finalize() external {
      if (isFinalized) revert();
      if (msg.sender != ethFundDeposit) revert(); // locks finalize to the ultimate ETH owner
      if(totalSupply < tokenCreationMin) revert();      // have to sell minimum to move to operational
      if(block.number <= fundingEndBlock && totalSupply != tokenCreationCap) revert();
      // move to operational
      isFinalized = true;
      if(!ethFundDeposit.send(this.balance)) revert();  // send the eth to Indicoin developers
    }

    /// @dev Allows contributors to recover their ether in the case of a failed funding campaign.
    function refund() external {
      if(isFinalized) revert();                       // prevents refund if operational
      if (block.number <= fundingEndBlock) revert(); // prevents refund until sale period is over
      if(totalSupply >= tokenCreationMin) revert();  // no refunds if we sold enough
      if(msg.sender == indiFundDeposit) revert();    // Indicoin developers not entitled to a refund
      uint256 indiVal = balances[msg.sender];
      if (indiVal == 0) revert();
      balances[msg.sender] = 0;
      totalSupply = safeSubtract(totalSupply, indiVal); // extra safe
      uint256 ethVal = indiVal / tokenExchangeRate;     // should be safe; previous throws covers edges
      LogRefund(msg.sender, ethVal);               // log it 
      if (!msg.sender.send(ethVal)) revert();       // if you're using a contract; make sure it works with .send gas limits
    }

}
