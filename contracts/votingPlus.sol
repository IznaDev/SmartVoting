// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

contract Voting is Ownable {

    //pour etre admin il suffit de déployer le contrat
    constructor() Ownable(msg.sender) {}

    // tableau au cas ou il y a des ex aequo
    uint[] winningProposalId;

    struct Voter {
        bool isRegistered;
        bool hasVoted;
        uint votedProposalId;
    }

    struct Proposal {
        string description;
        uint voteCount;
    }

    //j'ai  ajoute newVoteSession pour permettre de créer autant de session de vote qu'on veut mais de manière successive "synchrone".
    enum WorkflowStatus {
        VotesTallied, 
        newVoteSession, 
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
    address[] voters;

    //tableau des propositions faites pendant la session proposals. J'ai choisit un array pour faciliter le parcours des ifférentes propositions pendant le décompte
    Proposal[] _propolist;

    event VoterRegistered(address voterAddress);
    event VoterDeleted(address voterAddress); 
    event AllVotersDeleted();
    event WorkflowStatusChange(WorkflowStatus previousStatus, WorkflowStatus newStatus);
    event ProposalRegistered(uint proposalId);
    event Voted (address voter, uint proposalId);

    //creer une session vote globale
    function newVotingSession () external onlyOwner {
        require(currentStatus == WorkflowStatus.RegisteringVoters || currentStatus == WorkflowStatus.VotesTallied,"The current session doesn't allow voters to be removed!");
        emit WorkflowStatusChange(WorkflowStatus.VotesTallied, WorkflowStatus.newVoteSession);
        currentStatus = WorkflowStatus.newVoteSession;
    }

    //ajouter les voteurs
    function whitelist(address _add) external onlyOwner {

        require (currentStatus == WorkflowStatus.newVoteSession || currentStatus == WorkflowStatus.RegisteringVoters, "the current session doesn't allow voters to be added !");
       

        require(_add != address(0), "the address 0 is forbidden !");       
        require(!_whitelist[_add].isRegistered,"He's already registered !");

        _whitelist[_add].isRegistered = true;
        voters.push(_add);
        //même si ce contrat n'est pas adapté pour réaliser plusieurs session de vote je clear la liste des proposals
        //pour faire plusieurs session en mode debug
        delete _propolist;
        delete winningProposalId;

        emit VoterRegistered(_add);
        
        currentStatus = WorkflowStatus.RegisteringVoters;


    }

    //l'admin peut supprimer le voteurs de son choix
    function deleteVoter (address _add) external onlyOwner {
        require (currentStatus == WorkflowStatus.newVoteSession || currentStatus == WorkflowStatus.RegisteringVoters, "The current session doesn't allow voters to be removed!");
        require(_add != address(0), "the address 0 is forbidden !");       
        require(_whitelist[_add].isRegistered,"He's not registered !");

        _whitelist[_add].isRegistered = false;
        _whitelist[_add].hasVoted = false;
        _whitelist[_add].votedProposalId = 0;

        currentStatus = WorkflowStatus.RegisteringVoters;

    }

    //supprimer tous les voteurs
    function deleteAllVoters() external onlyOwner {
        require (currentStatus == WorkflowStatus.newVoteSession || currentStatus == WorkflowStatus.RegisteringVoters, "The current session doesn't allow voters to be removed!");
        require(voters.length > 0, "There is no voter !");

        for(uint i = 0;i<voters.length;i++) {
            _whitelist[voters[i]].isRegistered = false;
            _whitelist[voters[i]].hasVoted = false;
            _whitelist[voters[i]].votedProposalId = 0;
        }

        emit AllVotersDeleted();
        
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

    //dépouillement avec gestion des ex-aequo
   function voteTallying () external  onlyOwner{
        require(currentStatus == WorkflowStatus.VotingSessionEnded, "the Voting session is still open or has not start !");
         
        uint _voteCount;
        for(uint i =0;i<_propolist.length;i++) {
            if (_propolist[i].voteCount > _voteCount)
            {
                delete winningProposalId;
                winningProposalId.push(i);
                _voteCount = _propolist[i].voteCount;

            }
            else if (_propolist[i].voteCount == _voteCount)
            {
                winningProposalId.push(i);

            }
        }
        currentStatus = WorkflowStatus.VotesTallied;
    }

    // qui a gagné ?
   function getWinnerId() external view isWhitelisted() returns(uint[] memory) {
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
    function getWinningProposal () external view returns (Proposal[] memory) {
        require(currentStatus == WorkflowStatus.VotesTallied, " the votes are not tallied yet !");
        require(_propolist.length !=0,"no proposal available !");

        Proposal[]memory winningProposal = new Proposal[](winningProposalId.length);

        for(uint i=0; i<winningProposalId.length; i++) {

            winningProposal[i] = _propolist[winningProposalId[i]]; 
        } 

        return winningProposal;
    }

    //c'est une condition récurrente, j'en ai donc fait un modifier
    modifier isWhitelisted() {
        require(_whitelist[msg.sender].isRegistered,"You are not whitelisted !");
        _;
    }

}