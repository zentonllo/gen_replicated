-module(gen_replicated).
-export([start/2, stop/1, read/2, write/2, finishReading/3, finishWriting/2]).


-behaviour(gen_fsm).

-import(replica, [startReplica/1, stopReplica/1, readReplica/2, writeReplica/2 ]).
-export([init/1,wait/2, readingOp/2, writingOp/2, stopped/2, handle_event/3, handle_sync_event/4, handle_info/3, terminate/3, code_change/4 ]). 

%%%=========================================================================
%%%  API
%%%=========================================================================

start(NumReplica, Mod) ->
    gen_fsm:start_link(gen_replicated, {Mod, NumReplica}, []).

% I send an event to stop the cordinator which will turn out to switch down all of the replicas
stop(Server) ->
    gen_fsm:send_event(Server, stopCoord).

% I send an event with the Pid of the client. Notice that the message received will be sent by a replica    
read(Server, Req) ->
    Ref = self(),
    gen_fsm:send_event(Server, {read, {Ref, Req} }),
    receive 
      Result -> Result  
    end.
    
write(Server, Req) ->
    Ref = self(),
    gen_fsm:send_event(Server, {write, {Ref, Req} }),
    receive
       Result -> Result
    end.

    
% Using pattern matching, I differentiate cases when the replicas finish their task    
finishReading(Pid, _ReplicadPid, stop) ->
    stop(Pid);

finishReading(Pid, ReplicaPid, _) ->
    gen_fsm:send_event(Pid, {finishReading, ReplicaPid}).

finishWriting(Pid, stop) ->
    stop(Pid);

finishWriting(Pid, {updated, NewState} ) ->
    gen_fsm:send_event(Pid, {finishWriting, NewState});
    
finishWriting(Pid, _) ->
    gen_fsm:send_event(Pid, finishWriting).


    
%%%=========================================================================
%%%  gen_fsm states
%%%=========================================================================    

% I keep the state produced by Mod:init() to update it and send it to the replicas
init({Mod, NumReplica}) ->
    {ok, wait, {Mod:init(), startReplicas(Mod, NumReplica)}}.

% Stop all the replicas 
wait (stopCoord , {_ModState, ListReplicas} ) ->
    lists:map( fun replica:stopReplica/1, ListReplicas),
    {next_state, stopped, []};

% Keep track of the replicas which are currently reading     
wait( {read, Req}, {ModState, [Replica1 | RestReplicas]} ) ->
    replica:readReplica(Replica1, {{Req,Replica1,self()}, ModState}),
    { next_state, readingOp, {ModState, RestReplicas, [Replica1]} };

% Keep track of the replica which is currently writing (Notice that we can only write if the fsm is in the wait state, i.e, there is no current operations)    
wait( {write, Req}, {ModState, [Replica1 | RestReplicas]}) -> 
    replica:writeReplica(Replica1, {{Req,self()}, ModState}),
    { next_state, writingOp, {ModState, RestReplicas, Replica1} }.

% Cannot read and write concurrently    
readingOp( {write, {Ref,_Req}}, State) ->
    async(Ref, "Cannot write in this moment. Reading on progress" ),
    { next_state, readingOp, State};

% Stop reading and not_reading replicas    
readingOp( stopCoord, {_ModState, ListReplicas, ListReadingReplicas}) ->
    lists:map( fun replica:stopReplica/1, ListReplicas),
    lists:map( fun replica:stopReplica/1, ListReadingReplicas),
    { next_state, stopped, []};

% All the replicas are reading    
readingOp( {read, {Ref,_Req}}, {ModState, [], ListReadingReplicas} ) ->
        async(Ref, "All the replica processes are reading data at this moment. Wait until one of them finish"),
        { next_state, readingOp, {ModState, [], ListReadingReplicas}};

% One replica has finished reading. Could move to either wait or reading state        
readingOp( {finishReading, ReplicaPid}, {ModState, List, ListReadingReplicas}) ->
        case lists:delete(ReplicaPid,ListReadingReplicas) of
            [] -> { next_state, wait, {ModState, [ReplicaPid | List]} };
            List2 -> { next_state, readingOp, {ModState, [ReplicaPid | List], List2 } }
        end;
        
% Allow to read concurrently 
readingOp( {read, Req}, {ModState, [Replica1 | RestReplicas], ListReadingReplicas}) ->
    replica:readReplica(Replica1, {{Req,Replica1,self()}, ModState}),
    { next_state, readingOp, {ModState, RestReplicas, [Replica1 | ListReadingReplicas] }}.

% Stop the writing and the rest of replicas    
writingOp( stopCoord, {_ModState, ListReplicas, WriterReplica} ) ->
    lists:map( fun replica:stopReplica/1, ListReplicas),
    replica:stopReplica(WriterReplica),
    { next_state, stopped, []};

% Cannot write and read concurrently    
writingOp( {read, {Ref,_Req}}, State ) ->
   async(Ref, "Cannot perform reading operation. Writing on progress" ),
   { next_state, writingOp, State};

% The replica stopped writing, we may modify the state
writingOp(finishWriting, {ModState, List, ReplicaPid}) ->
    { next_state, wait, {ModState, [ReplicaPid | List]} };

writingOp({finishWriting, NewModState}, {_OldModState, List, ReplicaPid}) ->
    { next_state, wait, {NewModState, [ReplicaPid | List]} }.
 
% Stopped state. Cannot do nothing
stopped( stopCoord, State) ->
   { next_state, stopped, State };

stopped( {_Event, {Ref,_Req}}, State) ->
    async(Ref, "Cannot handle request. Server is stopped" ),
    { next_state, stopped, State }.
    
    
%%%=========================================================================
%%%  gen_fsm callbacks
%%%=========================================================================      

% These gen_fsm callbacks are set to the default values, since they don't need them 
code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.  
    
handle_event(_Event, StateName, State) ->
    {next_state, StateName, State}.

handle_info(_Info, StateName, State) ->
    {next_state, StateName, State}.

handle_sync_event(_Event, _From, StateName, State) ->
    Reply = ok,
    {reply, Reply, StateName, State}.

% Return a value to check that the coordinator terminated correctly  
terminate(_Reason, _State, _StateData) ->
    coordinator_terminated_ok.    
    
%%%=========================================================================
%%%  Internal Functions
%%%=========================================================================        

% Starting each of the replicas and joining all their Pid's in a List
startReplicas(Mod, NumReplica) ->
    case (NumReplica > 0) of
        true -> List = lists:map(fun replica:startReplica/1, lists:duplicate(NumReplica, Mod)),
                getPid(List);
        false -> io:format("The number of replicas should be strictly more than 0")
    end.
    

%% Taken from assignment 5. I filter the {ok, Pid} response in a first list to get only the Pid's     
getPid(List) ->
    lists:map( fun( {ok, Pid} )  -> Pid end, List).    
    

 % Taken from the lecture slides. Non-blocking rpc
async(Pid, Request) ->
    Pid ! Request.
