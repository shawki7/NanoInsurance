pragma solidity ^0.4.25;

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./FlightSuretyData.sol";

contract FlightSuretyApp {
    using SafeMath for uint256; 

    FlightSuretyData dataContract;

    bool private operational = true;

    uint8 private constant STATUS_CODE_UNKNOWN = 0;
    uint8 private constant STATUS_CODE_ON_TIME = 10;
    uint8 private constant STATUS_CODE_LATE_AIRLINE = 20;
    uint8 private constant STATUS_CODE_LATE_WEATHER = 30;
    uint8 private constant STATUS_CODE_LATE_TECHNICAL = 40;
    uint8 private constant STATUS_CODE_LATE_OTHER = 50;

    address private contractOwner;     

    struct Flight {
        address airline;
        uint256 timestamp;
        uint8 statusCode;
        address passenger;
        uint256 value;
    }
    mapping(bytes32 => Flight) private flights;

    modifier requireIsOperational() {
        require(operational == true, "Contract is currently not operational");
        _; 
    }

    modifier requireContractOwner() {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    modifier canAirlineCreateOrUpdate() {
        bool canCreate = (dataContract.getAirlinesCount() == 0) || (dataContract.isAirline(msg.sender) == true);
        require(canCreate == true, "this operation isn't available");
        _;
    }

    constructor(address dataContractAddress, address firstAirlineAddress) public {
        contractOwner = msg.sender;
        dataContract = FlightSuretyData(dataContractAddress);
        registerAirline(firstAirlineAddress);
    }
  
    function isOperational() public view returns(bool) {
        return operational; 
    }

    function registerAirline(address airlineAddress) public requireIsOperational() canAirlineCreateOrUpdate() {
        dataContract.registerAirline(airlineAddress);
    }

    function vote(address airlineAddress) public requireIsOperational() canAirlineCreateOrUpdate() {
        dataContract.voteAirline(airlineAddress, msg.sender);
    }

    function fund() public payable requireIsOperational() canAirlineCreateOrUpdate(){
        require(msg.value >= 10 ether, 'you must pay 10 ether');
        dataContract.fund.value(msg.value)(msg.sender);
    }

    function addFlight(address airline, string flight, uint256 timestamp) payable public requireIsOperational{
        require(msg.value <= 1 ether, 'cant pay more than 1');
        require(msg.value > 0, 'cant pay 0 ');

        bytes32 key = getFlightKey(airline, flight, timestamp);

        flights[key] = Flight({
            airline: airline,
            timestamp: timestamp,
            statusCode: STATUS_CODE_UNKNOWN,
            passenger: msg.sender,
            value: msg.value
        });
        dataContract.buy.value(msg.value)(msg.sender, key);
    }

    function updateFlightStatus ( address airline, string memory flight, uint256 timestamp, uint8 statusCode) internal requireIsOperational()  {
        bytes32 key = getFlightKey(airline, flight, timestamp);

        flights[key].statusCode = statusCode;
        if (statusCode == STATUS_CODE_LATE_AIRLINE) {
            dataContract.creditInsurees(key);
           
        } else {
            dataContract.closeInsurance(key);
        }
    }

    function getPassengerBalance(address add) view public requireIsOperational() returns(uint256 balance){
         return dataContract.getPassengerBalance(add);
    }

    function withdrawPassengerFunds() public requireIsOperational() {
        require(dataContract.getPassengerBalance(msg.sender) > 0, "Insufficient funds on passenger's balance");
        dataContract.pay(msg.sender);
    }

    function fetchFlightStatus(address airline, string flight, uint256 timestamp) public{
        uint8 index = getRandomIndex(msg.sender);

        bytes32 key = keccak256(abi.encodePacked(index, airline, flight, timestamp));
        oracleResponses[key] = ResponseInfo({
                                                requester: msg.sender,
                                                isOpen: true
                                            });

        emit OracleRequest(index, airline, flight, timestamp);
    }

    function setOperatingStatus(bool mode) public requireContractOwner {
        operational = mode;
    }




// region ORACLE MANAGEMENT

    // Incremented to add pseudo-randomness at various points
    uint8 private nonce = 0;

    // Fee to be paid when registering oracle
    uint256 public constant REGISTRATION_FEE = 1 ether;

    // Number of oracles that must respond for valid status
    uint256 private constant MIN_RESPONSES = 3;


    struct Oracle {
        bool isRegistered;
        uint8[3] indexes;
    }

    // Track all registered oracles
    mapping(address => Oracle) private oracles;

    // Model for responses from oracles
    struct ResponseInfo {
        address requester;                              // Account that requested status
        bool isOpen;                                    // If open, oracle responses are accepted
        mapping(uint8 => address[]) responses;          // Mapping key is the status code reported
                                                        // This lets us group responses and identify
                                                        // the response that majority of the oracles
    }

    // Track all oracle responses
    // Key = hash(index, flight, timestamp)
    mapping(bytes32 => ResponseInfo) private oracleResponses;

    // Event fired each time an oracle submits a response
    event FlightStatusInfo(address airline, string flight, uint256 timestamp, uint8 status);

    event OracleReport(address airline, string flight, uint256 timestamp, uint8 status);

    // Event fired when flight status request is submitted
    // Oracles track this and if they have a matching index
    // they fetch data and submit a response
    event OracleRequest(uint8 index, address airline, string flight, uint256 timestamp);


    // Register an oracle with the contract
    function registerOracle() external payable {
        // Require registration fee
        require(msg.value >= REGISTRATION_FEE, "Registration fee is required");

        uint8[3] memory indexes = generateIndexes(msg.sender);

        oracles[msg.sender] = Oracle({
            isRegistered : true,
            indexes : indexes
            });
    }

    function getMyIndexes() view external returns (uint8[3]) {
        require(oracles[msg.sender].isRegistered, "Not registered as an oracle");

        return oracles[msg.sender].indexes;
    }

    function submitOracleResponse(uint8 index, address airline, string flight, uint256 timestamp, uint8 statusCode) external {

        require((oracles[msg.sender].indexes[0] == index) || (oracles[msg.sender].indexes[1] == index) || (oracles[msg.sender].indexes[2] == index), "Index does not match oracle request");


        bytes32 key = keccak256(abi.encodePacked(index, airline, flight, timestamp));
        require(oracleResponses[key].isOpen, "Flight or timestamp do not match oracle request");

        oracleResponses[key].responses[statusCode].push(msg.sender);

        emit OracleReport(airline, flight, timestamp, statusCode);
        if (oracleResponses[key].responses[statusCode].length >= MIN_RESPONSES) {
            oracleResponses[key].isOpen = false;
            emit FlightStatusInfo(airline, flight, timestamp, statusCode);

            updateFlightStatus(airline, flight, timestamp, statusCode);
        }
    }


    function getFlightKey(address airline, string flight, uint256 timestamp) pure internal returns (bytes32){
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    // Returns array of three non-duplicating integers from 0-9
    function generateIndexes(address account) internal returns (uint8[3]) {
        uint8[3] memory indexes;
        indexes[0] = getRandomIndex(account);

        indexes[1] = indexes[0];
        while (indexes[1] == indexes[0]) {
            indexes[1] = getRandomIndex(account);
        }

        indexes[2] = indexes[1];
        while ((indexes[2] == indexes[0]) || (indexes[2] == indexes[1])) {
            indexes[2] = getRandomIndex(account);
        }

        return indexes;
    }

    // Returns array of three non-duplicating integers from 0-9
    function getRandomIndex(address account) internal returns (uint8) {
        uint8 maxValue = 10;

        // Pseudo random number...the incrementing nonce adds variation
        uint8 random = uint8(uint256(keccak256(abi.encodePacked(blockhash(block.number - nonce++), account))) % maxValue);

        if (nonce > 250) {
            nonce = 0;
            // Can only fetch blockhashes for last 256 blocks so we adapt
        }

        return random;
    }

    // endregion

}   
