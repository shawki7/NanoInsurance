pragma solidity ^0.4.25;

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

contract FlightSuretyData {
    using SafeMath for uint256;

    uint public MAX_AUTO_REGISTERED_AIRLINES = 4;

    uint public INSURANCE_STATUS_UNKNOWN = 0;
    uint public INSURANCE_STATUS_IN_PROGRESS = 1;
    uint public INSURANCE_STATUS_PAID = 1;
    uint public INSURANCE_STATUS_CLOSED = 2;


    address private contractOwner;                                      
    bool private operational = true;                                    
    mapping (address=>bool) private authorizedCallers;

    struct Airline {
        bool isExists;
        uint256 registeredNumber;
        bool needApprove;
        bool isFunded;
        Votes votes;
        uint256 minVotes;
    }
    struct Votes{
        uint votersCount;
        mapping(address => bool) voters;
    }

    uint256 private airlinesCount = 0;
    mapping(address => Airline) private airlines;

    struct InsuranceInfo{
        address passenger;
        uint256 value;
        uint status;
    }
    mapping(bytes32 => InsuranceInfo) private insurances;
    mapping(address => uint256) private passengerBalances;
 
    constructor() public {
        contractOwner = msg.sender;
    }

    modifier requireIsOperational() {
        require(operational == true, "Contract is currently not operational");
        _;
    }

    modifier requireContractOwner() {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }
    modifier requireAuthorizedCaller(address contractAddress) {
         require(authorizedCallers[contractAddress] == true, "Not Authorized Caller");
        _;
    }

    modifier isAirlineExists(address airlineAddress) {
        require(airlines[airlineAddress].isExists, "Airline does't exist");
        _;
    }

    modifier isAirlineApproved(address airlineAddress) {
        Airline airline = airlines[airlineAddress];
        require((airline.needApprove == false) || (airline.votes.votersCount >= airline.minVotes), "Need approval from other Airlines");
        _;
    }

    function isOperational() public view returns (bool) {
        return operational;
    }

    function setOperatingStatus(bool mode) external requireContractOwner {
        operational = mode;
    }

    function authorizeCaller(address contractAddress) external requireContractOwner requireIsOperational {
        authorizedCallers[contractAddress] = true;
    }
  
    function getAirlinesCount() public view returns (uint256) {
        return airlinesCount;
    }
    
    function registerAirline(address airlineAddress) external requireIsOperational{
        airlines[airlineAddress] = Airline({
            isExists: true,
            registeredNumber: airlinesCount,
            needApprove: airlinesCount >= MAX_AUTO_REGISTERED_AIRLINES,
            votes: Votes(0),
            isFunded: false,
            minVotes: airlinesCount.add(1).div(2)
        });

        airlinesCount = airlinesCount.add(1);
    }
  
    function voteAirline(address airlineAddress, address voterAddress) external isAirlineExists(airlineAddress) requireIsOperational returns (bool){
        require(airlines[airlineAddress].votes.voters[voterAddress] == false, "Airline already voted by this account");

        airlines[airlineAddress].votes.votersCount = airlines[airlineAddress].votes.votersCount.add(1);
        airlines[airlineAddress].votes.voters[voterAddress] = true;

        airlines[airlineAddress].needApprove = airlines[airlineAddress].votes.votersCount < airlines[airlineAddress].minVotes;
        return airlines[airlineAddress].needApprove;
    }

    function buy(address passenger, bytes32 flightKey) external requireIsOperational payable {
        insurances[flightKey] = InsuranceInfo({
            passenger: passenger,
            value: msg.value,
            status: INSURANCE_STATUS_IN_PROGRESS
        });
    }
  
    function creditInsurees(bytes32 flightKey) external requireIsOperational {
        InsuranceInfo insurance = insurances[flightKey];
        if (insurance.status == INSURANCE_STATUS_IN_PROGRESS) {
            uint256 balance = passengerBalances[insurance.passenger];
            passengerBalances[insurance.passenger] = balance.add(getInsurancePayoutValue(flightKey));
            insurance.status = INSURANCE_STATUS_PAID;
        }
    }

    function closeInsurance(bytes32 flightKey) external requireIsOperational{
        if (insurances[flightKey].status != INSURANCE_STATUS_UNKNOWN) {
            insurances[flightKey].status = INSURANCE_STATUS_CLOSED;
        }
    }

    function getInsurancePayoutValue(bytes32 flightKey) view public requireIsOperational returns(uint256){
        InsuranceInfo insurance = insurances[flightKey];
        uint256 insurancePayoutValue = insurance.value.div(2);
        return insurancePayoutValue.add(insurance.value);
    }

    function getPassengerBalance(address passengerAddress) view public requireIsOperational returns(uint256){
        return passengerBalances[passengerAddress];
    }

    function pay(address passengerAddress) external requireIsOperational {
        uint256 balance = passengerBalances[passengerAddress];
        require(address(this).balance > balance, 'Not enough contact balance');
        passengerBalances[passengerAddress] = 0;
        passengerAddress.transfer(balance);
    }
 
    function fund(address airlineAddress) payable external requireIsOperational() isAirlineExists(airlineAddress) isAirlineApproved(airlineAddress){
        airlines[airlineAddress].isFunded = true;
    }

    function getFlightKey(address airline, string memory flight, uint256 timestamp) pure internal returns (bytes32) {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    function isAirline(address airlineAddress) public view requireIsOperational() returns (bool) {
        return airlines[airlineAddress].isExists;
    }

  
}

