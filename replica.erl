
-module(replica).

-behaviour(gen_fsm).

-import(gen_replicated, [finishReading/3, finishWriting/2]).
-export([startReplica/1, stopReplica/1, readReplica/2, writeReplica/2]).
-export([init/1, wait/3, working/2, handle_event/3, handle_sync_event/4, handle_info/3, terminate/3, code_change/4]). 

%%%=========================================================================
%%%  API
%%%=========================================================================

startReplica(Mod) -> 
    gen_fsm:start_link(replica, Mod, []).

% Make the replicas to either read or work. Notice that this is similar to the Worker fsm used in assignment 5 but this time I don't differentiate readerReplicas and writerReplicas     
% I make the first event as sync to wait till the working state is set in the replica fsm
readReplica(Pid, Req) ->
     gen_fsm:sync_send_event(Pid, {readReplica, Req}),
     gen_fsm:send_event(Pid, startWorkingReading).

writeReplica(Pid, Req) ->
     gen_fsm:sync_send_event(Pid, {writeReplica, Req}),
     gen_fsm:send_event(Pid, startWorkingWriting).

% Shutdown the replica fsm. Notice that we warn the client about this through the terminate function (I send them an async message)since we wave their Pid saved in the state
stopReplica(Pid) ->
     gen_fsm:stop(Pid).
     
%%%=========================================================================
%%%  gen_fsm states
%%%=========================================================================    

init(Mod) ->
    {ok, wait, Mod}.

% Save all the data in order to work or to either yield an error to the client or working with that  
wait({readReplica, { {{Ref,Req},SelfPid,CoordPid}, ModState} }, _From, Mod) ->
    {reply, ok, working, {Mod,Ref,SelfPid,Req,CoordPid,ModState}};
    
wait({writeReplica, {{{Ref, Req},CoordPid}, ModState}}, _From, Mod) ->
    {reply, ok, working, {Mod,Ref,Req,CoordPid,ModState}}.

% Using the try-catch block I assure that the client will get a response eventually
working( startWorkingReading, {Mod,ClientPid,SelfPid,Req,CoordPid,ModState}) ->
    try Mod:handle_read(Req, ModState) of
        {reply, Reply} -> async(ClientPid, Reply), finishReading(CoordPid, SelfPid, reply);
        stop -> async(ClientPid, {'ABORTED', server_stopped}), finishReading(CoordPid, SelfPid, stop)
    catch 
        _ : Val -> async(ClientPid, {'ABORTED', exception, Val}), finishReading(CoordPid, SelfPid, exception)
    end,
    { next_state, wait, Mod};   
    
working( startWorkingWriting, {Mod,ClientPid,Req,CoordPid,ModState} ) ->
   try Mod:handle_write(Req, ModState) of 
        {noupdate, Reply } -> async(ClientPid, Reply),finishWriting(CoordPid, noupdate );
        {updated, Reply, NewState} -> async(ClientPid, Reply), finishWriting(CoordPid, {updated, NewState});
        stop -> async(ClientPid, {'ABORTED', server_stopped}),finishWriting(CoordPid, stop)
    catch 
        _ : Val -> async(ClientPid, {'ABORTED', exception, Val}), finishWriting(CoordPid, exception)
    end,
    { next_state, wait, Mod}.
   

   
%%%=========================================================================
%%%  gen_fsm callbacks
%%%=========================================================================     
   
% These gen_fsm callbacks are set to the default values, since for some of them I don't require them   
code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.  
    
   
handle_event(_Event, StateName, State) ->
    {next_state, StateName, State}.

handle_info(_Info, StateName, State) ->
    {next_state, StateName, State}.

handle_sync_event(_Event, _From, StateName, State) ->
    Reply = ok,
    {reply, Reply, StateName, State}.
  
terminate(_Reason, wait, _StateData) ->
    replica_stopped_correctly;

terminate(_Reason, working, {_Mod, ClientPid, _SelfPid, _Req, _CoordPid, _ModState}) ->
    async(ClientPid, {'ABORTED', server_stopped});
    
terminate(_Reason, working, {_Mod, ClientPid, _Req, _CoordPid, _ModState}) ->
    async(ClientPid, {'ABORTED', server_stopped}).
    
    

    
%%%=========================================================================
%%%  Internal Functions
%%%=========================================================================  

 % Taken from the lecture slides. Non-blocking rpc
async(Pid, Request) ->
    Pid ! Request.


