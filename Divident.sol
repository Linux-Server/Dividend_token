pragma solidity ^0.4.25;

// ----------------------------------------------------------------------------
// Safe maths
// ----------------------------------------------------------------------------
library SafeMath {
  function add(uint256 a, uint256 b) internal pure returns (uint256 c) {
      c = a + b;
      require(c >= a);
  }
  function sub(uint256 a, uint256 b) internal pure returns (uint256 c) {
      require(b <= a);
      c = a - b;
  }
  function mul(uint256 a, uint256 b) internal pure returns (uint256 c) {
      c = a * b;
      require(a == 0 || c / a == b);
  }
  function div(uint256 a, uint256 b) internal pure returns (uint256 c) {
      require(b > 0);
      c = a / b;
  }
  function mod(uint256 a, uint256 b) internal pure returns (uint256) {
    require(b != 0);
    return a % b;
  }
}

// ----------------------------------------------------------------------------
// ERC Token Standard #20 Interface
// https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20.md
// ----------------------------------------------------------------------------
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address _who) external view returns (uint256);
    function allowance(address _owner, address _spender)  external view returns (uint256);
    function transfer(address _to, uint256 _value) external returns (bool);
    function approve(address _spender, uint256 _value)  external returns (bool);
    function transferFrom(address _from, address _to, uint256 _value)  external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value  );
    event Approval(address indexed owner, address indexed spender, uint256 value  );
}

// ----------------------------------------------------------------------------
// Contract function to receive approval and execute function in one call
//
// Borrowed from MiniMeToken
// ----------------------------------------------------------------------------
contract ApproveAndCallFallBack {
    function receiveApproval(address from, uint256 tokens, address token, bytes memory data) public;
}

// ----------------------------------------------------------------------------
// Owned contract
// ----------------------------------------------------------------------------
contract Owned {
    address public owner;
    address public newOwner;
    event OwnershipTransferred(address indexed _from, address indexed _to);

    constructor() public {
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    function transferOwnership(address _newOwner) public onlyOwner {
        newOwner = _newOwner;
    }
    function acceptOwnership() public {
        require(msg.sender == newOwner);
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
        newOwner = address(0);
    }
}

// ----------------------------------------------------------------------------
// Implementation of the basic standard token.
// https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20.md
// ----------------------------------------------------------------------------

contract DividendToken is IERC20, Owned {
    using SafeMath for uint256;


    //mapping (address => uint256) private accounts;
    mapping (address => mapping (address => uint256)) private allowed_;
    string public name;
    string public symbol;
    uint256 private totalSupply_;
    uint8 public decimals;

    bool public mintable = true;
    bool public transferable = false;

    // Dividends
    uint256 constant pointMultiplier = 10e32;
    address public dividendTokenAddress;

    struct Account {
        uint256 balance;
        uint256 lastDivPoints;
        uint256 lastEthPoints;
    }
    mapping(address => Account) public accounts;

    mapping(address => uint256) public totalDividendPoints;
    mapping(address => uint256) public unclaimedDividends;
    mapping(address => mapping(address => uint256)) public unclaimedDividendByAccount;  // [account][token]

    event Mint(address indexed to, uint256 amount);
    event MintStarted();
    event MintFinished();
    event TransfersEnabled();
    event TransfersDisabled();

    event DividendReceived(uint256 time, address indexed sender, address indexed token, uint256 amount);
    event WithdrawalDividends(address indexed holder, address indexed token, uint256 amount);
    event LogUint(uint256 amount, string msglog);

    // ------------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------------
    constructor() public {
        name = "Sachin's Dividend Token";
        symbol = "SAM";
        decimals = 0;
        totalSupply_ = 10 * 10**uint(decimals);
        transferable = true;
        accounts[owner].balance = totalSupply_;
        _initDividends();
        emit Transfer(address(0), owner, totalSupply_);
    }

    modifier canMint() {
        require(mintable);
        _;
    }

    function totalSupply() public view returns (uint256) {
        return totalSupply_;    // Bok add the diff of accountzero and factor in amount
    }

    function balanceOf(address _owner) public view returns (uint256) {
        return accounts[_owner].balance;
    }

    function allowance(  address _owner,  address _spender )  public  view  returns (uint256) {
        return allowed_[_owner][_spender];
    }

    function approve(address _spender, uint256 _value) public returns (bool) {
        require(transferable);
        allowed_[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }


    function transfer(address _to, uint256 _value) public returns (bool) {
        require(transferable);
        require(_value <= accounts[msg.sender].balance);   // Bok not needed
        require(_to != address(0));                        // might not restrict transfer to account zero (erc20)

        // Added for dividends
        _updateAccount(msg.sender);
        _updateAccount(_to);

        accounts[msg.sender].balance = accounts[msg.sender].balance.sub(_value);
        accounts[_to].balance = accounts[_to].balance.add(_value);
        emit Transfer(msg.sender, _to, _value);
        return true;
    }

    function transferFrom(  address _from,  address _to,uint256 _value )  public returns (bool) {
        require(transferable);
        require(_value <= accounts[_from].balance);  // Bok not needed
        require(_value <= allowed_[_from][msg.sender]); // Bok not needed
        require(_to != address(0));   // might not restrict transfer to account zero

        // Added for dividends
        _updateAccount(_from);
        _updateAccount(_to);

        accounts[_from].balance = accounts[_from].balance.sub(_value);
        accounts[_to].balance = accounts[_to].balance.add(_value);
        allowed_[_from][msg.sender] = allowed_[_from][msg.sender].sub(_value);
        emit Transfer(_from, _to, _value);
        return true;
    }


    /**
     * @dev Increase the amount of tokens that an owner allowed to a spender.
     * approve should be called when allowed_[_spender] == 0. To increment
     * allowed value is better to use this function to avoid 2 calls (and wait until
     * the first transaction is mined)
     * From MonolithDAO Token.sol
     */
    function increaseApproval(address _spender, uint256 _addedValue) public returns (bool) {
        allowed_[msg.sender][_spender] = (allowed_[msg.sender][_spender].add(_addedValue));
        emit Approval(msg.sender, _spender, allowed_[msg.sender][_spender]);
        return true;
    }

    function decreaseApproval(address _spender, uint256 _subtractedValue) public returns (bool) {
        uint256 oldValue = allowed_[msg.sender][_spender];
        if (_subtractedValue >= oldValue) {
          allowed_[msg.sender][_spender] = 0;
        } else {
          allowed_[msg.sender][_spender] = oldValue.sub(_subtractedValue);
        }
        emit Approval(msg.sender, _spender, allowed_[msg.sender][_spender]);
        return true;
    }

    // ------------------------------------------------------------------------
    // Mint & Burn functions, both interrnal and external
    // ------------------------------------------------------------------------
    function _mint(address _account, uint256 _amount) internal {
        require(_account != 0);

        // Added for dividends
        _updateAccount(_account);

        totalSupply_ = totalSupply_.add(_amount);
        accounts[_account].balance = accounts[_account].balance.add(_amount);
        emit Transfer(address(0), _account, _amount);
    }

    function _burn(address _account, uint256 _amount) internal {
        require(_account != 0);
        require(_amount <= accounts[_account].balance);

        // Added for dividends
        _updateAccount(_account);

        totalSupply_ = totalSupply_.sub(_amount);
        accounts[_account].balance = accounts[_account].balance.sub(_amount);
        emit Transfer(_account, address(0), _amount);
    }

    function _burnFrom(address _account, uint256 _amount) internal {
        require(_amount <= allowed_[_account][msg.sender]);
        allowed_[_account][msg.sender] = allowed_[_account][msg.sender].sub(_amount);
        _burn(_account, _amount);
    }

    function mint(address _to, uint256 _amount) public onlyOwner canMint returns (bool) {
        _mint(_to, _amount);
        emit Mint(_to, _amount);
        return true;
    }

    function burn(uint256 _value)  public {
        _burn(msg.sender, _value);
    }

    function burnFrom(address _from, uint256 _value) public {
        _burnFrom(_from, _value);
    }

    // ------------------------------------------------------------------------
    // Safety to start and stop minting new tokens.
    // ------------------------------------------------------------------------

    function startMinting() public onlyOwner returns (bool) {
        mintable = true;
        emit MintStarted();
        return true;
    }

    function finishMinting() public onlyOwner canMint returns (bool) {
        mintable = false;
        emit MintFinished();
        return true;
    }

    // ------------------------------------------------------------------------
    // Safety to stop token transfers
    // ------------------------------------------------------------------------

    function enableTransfers() public onlyOwner {
        require(!transferable);
        transferable = true;
        emit TransfersEnabled();
    }

    function disableTransfers() public onlyOwner {
        require(transferable);
        transferable = false;
        emit TransfersDisabled();
    }

    //------------------------------------------------------------------------
    // Dividends
    //------------------------------------------------------------------------
    function dividendsOwing(address _account, address _token) external view returns(uint256) {
        _dividendsOwing(_account, _token);
    }

    function _dividendsOwing(address _account, address _token) internal view returns(uint256) {
        uint256 lastPoints;
        if (_token == address(0x0)) {
              lastPoints = accounts[_account].lastEthPoints;
        } else if (_token == dividendTokenAddress) {
              lastPoints = accounts[_account].lastDivPoints;
        }
        uint256 newDividendPoints = totalDividendPoints[_token].sub(lastPoints);
        return (accounts[_account].balance * newDividendPoints) / pointMultiplier;
    }

    //------------------------------------------------------------------------
    // Dividends: Token Transfers
    //------------------------------------------------------------------------
     function _updateAccount(address _account) internal {
        if (accounts[_account].lastDivPoints < totalDividendPoints[dividendTokenAddress]) {
              _updateAccountByToken(_account,dividendTokenAddress);
        }
        if (accounts[_account].lastEthPoints < totalDividendPoints[address(0x0)]) {
              _updateAccountByToken(_account,address(0x0));
        }
     }

    function _updateAccountByToken(address _account, address _token) internal {
        uint256 _owing = _dividendsOwing(_account, _token);
        if (_owing > 0) {
            unclaimedDividendByAccount[_account][_token] = unclaimedDividendByAccount[_account][_token].add(_owing);
        }
    }

    //------------------------------------------------------------------------
    // Dividends: Token Deposits
    //------------------------------------------------------------------------

    function depositTokenDividend(uint256 _amount) external  {
        require(_amount > 0 );
        // accept tokens
        require(IERC20(dividendTokenAddress).transferFrom(msg.sender, address(this), _amount));
        _depositDividends(_amount, dividendTokenAddress);
    }

    function _depositDividends(uint256 _amount, address _token) internal {
        // Convert deposit into points
        totalDividendPoints[_token] += (_amount * pointMultiplier ) / totalSupply();
        unclaimedDividends[_token] += _amount;
        emit DividendReceived(now, msg.sender, _token, _amount);
    }

    //------------------------------------------------------------------------
    // Dividends: Claim accrued dividends
    //------------------------------------------------------------------------
    function withdrawDividends () public  {
        _updateAccount(msg.sender);
        if (unclaimedDividendByAccount[msg.sender][dividendTokenAddress]>0) {
          _withdrawDividendsByToken(dividendTokenAddress);
        }
        if (unclaimedDividendByAccount[msg.sender][address(0)]>0) {
            _withdrawDividendsByToken(address(0));
        }
    }

    function _withdrawDividendsByToken(address _token) internal  {
        uint256 _unclaimed = unclaimedDividendByAccount[msg.sender][_token];
        unclaimedDividends[_token] = unclaimedDividends[_token].sub(_unclaimed);
        unclaimedDividendByAccount[msg.sender][_token] = 0;

        _transferDividendTokens(_token,msg.sender, _unclaimed );
        emit WithdrawalDividends(msg.sender, _token, _unclaimed);
    }

    function _transferDividendTokens(address _token, address _account, uint256 _amount) internal view   {
        // transfer dividends, will need to be replaced
        if (_token == address(0x0)) {
             transfer(_account, _amount);  //  bok google transfer send ethereum and check the need for require()
        } else if (_token == dividendTokenAddress) {
             require(IERC20(_token).transfer(_account, _amount));
        }
    }

    //------------------------------------------------------------------------
    // Dividends: Helper functions
    //------------------------------------------------------------------------
    function setDividendTokenAddress (address _token) public onlyOwner {
        require(_token != address(0));
        dividendTokenAddress = IERC20(_token);
    }

    function _initDividends() internal {
        dividendTokenAddress = IERC20(0x89d24A6b4CcB1B6fAA2625fE562bDD9a23260359);
        _depositDividends(msg.value,address(0x0));
    }

    // ------------------------------------------------------------------------
    // Accept ETH deposits as dividends
    // ------------------------------------------------------------------------
    function () public payable {
        require(msg.value > 0);
        _depositDividends(msg.value,address(0x0));
    }

    // ------------------------------------------------------------------------
    // Owner can transfer out any accidentally sent ERC20 tokens, please restrict or remove
    // ------------------------------------------------------------------------
    function transferAnyERC20Token(address tokenAddress, uint256 tokens) public onlyOwner returns (bool success) {
        return IERC20(tokenAddress).transfer(owner, tokens);
    }
}