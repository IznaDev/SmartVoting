// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

contract Voting is Ownable {

    //pour etre admin il suffit de déployer le contrat
    constructor() Ownable(msg.sender) {}

    uint winningProposalId;

    struct Voter {
        bool isRegistered;
        bool hasVoted;
        uint votedProposalId;
    }

    struct Proposal {
        string description;
        uint voteCount;
    }

    //j'ai mis VotesTallied en premier pour interdire l'accès à la fonction proposalRegisteringSessionStart() avant d'ajouter des voteurs
    enum WorkflowStatus { 
        VotesTallied ,
        RegisteringVoters, 
        ProposalsRegistrationStarted, 
        ProposalsRegistrationEnded, 
        VotingSessionStarted, 
        VotingSessionEnded
        }

    //variable du type de l'enum pour enregistrer le statut actuel et ainsi ordonner les sessions
    WorkflowStatus public currentStatus; 
   
    // la whitelist !
    mapping(address => Voter) _whitelist;

    //tableau des propositions faites pendant la session proposals. J'ai choisit un array pour faciliter le parcours des ifférentes propositions pendant le décompte
    Proposal[] _propolist;

    event VoterRegistered(address voterAddress);
    event WorkflowStatusChange(WorkflowStatus previousStatus, WorkflowStatus newStatus);
    event ProposalRegistered(uint proposalId);
    event Voted (address voter, uint proposalId);

    //ajouter les voteurs
    function whitelist(address _add) external onlyOwner {

        //deux situations possibles pour le statut précédent au moment de l'appel de cette fonction
        // VotesTallied ou registering voters si ce n'est pas le premier qu'on ajoute
        if(currentStatus == WorkflowStatus.VotesTallied) {
            emit WorkflowStatusChange(WorkflowStatus.VotesTallied, WorkflowStatus.RegisteringVoters);
            currentStatus = WorkflowStatus.RegisteringVoters;
        }
        else if (currentStatus != WorkflowStatus.VotesTallied && currentStatus != WorkflowStatus.RegisteringVoters)
        {
            revert("The current session does not allow voters to be added !");
        }

        require(_add != address(0), "the address 0 is forbidden !");       
        require(!_whitelist[_add].isRegistered,"He's already registered !");

        _whitelist[_add].isRegistered = true;
        //même si ce contrat n'est pas adapté pour réaliser plusieurs session de vote je clear la liste des proposals
        //pour faire plusieurs session en mode debug
        delete _propolist;
        winningProposalId = 0;

        emit VoterRegistered(_add);


    }

    //ouverture de la session des propostions
    function proposalRegisteringSessionStart () external onlyOwner {
        require(currentStatus == WorkflowStatus.RegisteringVoters,"The current session does not allow you to open porposals session !");
        emit WorkflowStatusChange(WorkflowStatus.RegisteringVoters, WorkflowStatus.ProposalsRegistrationStarted);
        currentStatus = WorkflowStatus.ProposalsRegistrationStarted; 
    }

    //fermeture de la session des propositions
    function proposalRegisteringSessionEnd () external onlyOwner {
        require(currentStatus == WorkflowStatus.ProposalsRegistrationStarted,"The proposal registering Session is already closed !");
        emit WorkflowStatusChange(WorkflowStatus.ProposalsRegistrationStarted, WorkflowStatus.ProposalsRegistrationEnded);
        currentStatus = WorkflowStatus.ProposalsRegistrationEnded;
    }

    //faire sa proposition
    function myProposal(string memory _description) isWhitelisted() external {
        require (currentStatus == WorkflowStatus.ProposalsRegistrationStarted, "The proposal registration session is closed !");
        require(bytes(_description).length != 0," Your proposal description is empty");
        Proposal memory p;
        p.description = _description;
        _propolist.push(p);
        uint proposalId = _propolist.length - 1;
        emit ProposalRegistered(proposalId);
    }

    //ouverture de la session de vote
    function votingSessionStart() external onlyOwner {
        require(currentStatus == WorkflowStatus.ProposalsRegistrationEnded, "The current session does not allow you to open voting session !");
        emit WorkflowStatusChange(WorkflowStatus.ProposalsRegistrationEnded,WorkflowStatus.VotingSessionStarted);
        currentStatus = WorkflowStatus.VotingSessionStarted;
    }

    //fermeture de la session de vote
    function votingSessionEnd() external onlyOwner {
        require(currentStatus == WorkflowStatus.VotingSessionStarted," The voting session is closed !");
        emit WorkflowStatusChange(WorkflowStatus.VotingSessionStarted ,WorkflowStatus.VotingSessionEnded);
        currentStatus = WorkflowStatus.VotingSessionEnded;
    }

    //voter
    function myVoiceto (uint _votedProposalId) isWhitelisted() external {
        require (currentStatus == WorkflowStatus.VotingSessionStarted, "The Voting session is closed!");
        require(_votedProposalId < _propolist.length, "This proposal ID doesn't exist !");
        require(!_whitelist[msg.sender].hasVoted,"you have already voted !");
        

        _whitelist[msg.sender].hasVoted = true;
        _whitelist[msg.sender].votedProposalId = _votedProposalId;
        _propolist[_votedProposalId].voteCount++;

        emit Voted(msg.sender, _votedProposalId);
    }

    //dépouillement ( je ne gère pas les exeaquo car ce n'était pas demandé. voir le votingplus.sol
    function voteTallying () external onlyOwner{
        require(currentStatus == WorkflowStatus.VotingSessionEnded, "the Voting session is still open or has not start !");
         
        uint _voteCount;
        for(uint i =0;i<_propolist.length;i++) {
            if (_propolist[i].voteCount > _voteCount)
            {
                winningProposalId = i;
                _voteCount = _propolist[i].voteCount;
            }

        }
        emit WorkflowStatusChange(WorkflowStatus.VotingSessionEnded, WorkflowStatus.VotesTallied);
        currentStatus = WorkflowStatus.VotesTallied;
    }

    // qui a gagné ?
   function getWinnerId() external view isWhitelisted() returns(uint) {
        require(currentStatus == WorkflowStatus.VotesTallied," the votes were not tallied yet !");
        return winningProposalId;
    }

    //qu'est ce qu'il a voté cuila ?
    function whatIsHisVote (address _add) external view isWhitelisted() returns (uint) {
        require(currentStatus == WorkflowStatus.VotesTallied, " the votes were not tallied yet !");
        require(_whitelist[_add].isRegistered, "He is not a voter !");
        require(_whitelist[_add].hasVoted,"This voter has not voted !");
        

        return (_whitelist[_add].votedProposalId);
    }

    //que dit la proposition gagnante ?
    function getWinningProposal () external view returns (Proposal memory) {
        require(currentStatus == WorkflowStatus.VotesTallied, " the votes are not tallied yet !");
        require(_propolist.length !=0,"no proposal available !");

        return(_propolist[winningProposalId]);
    }

    //c'est une condition récurrente, j'en ai donc fait un modifier
    modifier isWhitelisted() {
        require(_whitelist[msg.sender].isRegistered,"You are not whitelisted !");
        _;
    }

}