-module(tests_gen_replicated).

-import(gen_replicated, [start/2, stop/1, read/2, write/2]).
-export([testing/1, testing2/1, testing3/1, init/0, handle_read/2, handle_write/2]).

% Add some contacts, get a couple of existiong ones from the list and finally stop the server. Then, it's tried to keep sending requests although the server is stopped
testing(NumReplicas) ->
    {ok,Server} = gen_replicated:start(NumReplicas, tests_gen_replicated),
    Rep1 = gen_replicated:write(Server, {add, {"Person1", "falseStreet123", "21332"} } ),
    Rep2 = gen_replicated:write(Server, {add, {"Person2", "falseStreet9", "2131532"} } ),
    Rep3 = gen_replicated:write(Server, {add, {"Person3", "falseStreet54", "21321332"} } ),
    Rep4 = gen_replicated:read(Server, {find, "Person1"}),
    Rep5 = gen_replicated:read(Server, {find, "Person3"}),
    Rep6 = gen_replicated:stop(Server),
    Rep7 = gen_replicated:read(Server, {add, {"Person3", "falseStreet123", "21332"} }),
    {Rep1, Rep2, Rep3, Rep4, Rep5, Rep6, Rep7}.

% Trying to add, delete and update different contacts. Should yield some errors (updating a non-added contact and removing a non-existing contact) 
% to proof that the code is correct    
testing2(NumReplicas) ->
    {ok,Server} = gen_replicated:start(NumReplicas, tests_gen_replicated),
    Rep1 = gen_replicated:write(Server, {add, {"Person1", "falseStreet123", "21332"} } ),
    Rep2 = gen_replicated:write(Server, {delete, "Person1" } ),
    Rep3 = gen_replicated:write(Server, {update, {"Person1", "newFalseStreet", "112"}} ),
    Rep4 = gen_replicated:write(Server, {add, {"Person2", "falseStreet5", "22"} } ),
    Rep5 = gen_replicated:write(Server, {update, {"Person2", "newFalseStreet2", "31"}}),
    Rep6 = gen_replicated:write(Server, {delete, "Person1"}),
    {Rep1, Rep2, Rep3, Rep4, Rep5, Rep6}.

% Add some contacts, find an existing one and find a non-added one. The latter makes the server to stop. Then it is tried to stop the server again (Yielding no errors)
% and it is sended another request which will be denied since the server is stopped
testing3(NumReplicas) ->
    {ok,Server} = gen_replicated:start(NumReplicas, tests_gen_replicated),
    Rep1 = gen_replicated:write(Server, {add, {"Person1", "falseStreet123", "21332"} } ),
    Rep2 = gen_replicated:write(Server, {add, {"Person2", "falseStreet53", "23"} } ),
    Rep3 = gen_replicated:write(Server, {add, {"Person3", "falseStreet76", "42"} } ),
    Rep4 = gen_replicated:read(Server, {find, "Person1"}),
    Rep5 = gen_replicated:read(Server, {find, "Person4"}),
    Rep6 = gen_replicated:stop(Server),
    Rep7 = gen_replicated:read(Server, {add, {"Person3", "falseStreet35", "213"} }),
    {Rep1, Rep2, Rep3, Rep4, Rep5, Rep6, Rep7}.
    
% Idea and some code taken from pb.erl and pbtest.erl used during the lectures. The handlers return every possible 
% value (Exceptions, stop events, updatings...) to try every branch of the code
init() -> dict:new().
handle_write({delete, Name}, Contacts) ->
    case dict:is_key(Name, Contacts) of
        false -> {noupdate, {couldnt_find_contact, Name}  };
        true -> {updated , {Name ,removed_ok}, dict:erase(Name, Contacts) }
    end;

handle_write({add, {Name, _Street, _PostCode} = Contact}, Contacts) ->
    case dict:is_key(Name, Contacts) of 
        false -> {updated, {added_contact, Name}, dict:store(Name, Contact, Contacts)};
        true  -> throw({Name, already_added})
    end;
handle_write({update, {Name, _, _} = Contact}, Contacts) ->
    case dict:is_key(Name, Contacts) of 
        false -> throw({Name, not_added_cannot_update});
        true  -> {updated, {Name,contact_updated}, dict:store(Name, Contact, Contacts)}
    end.
    
handle_read({find, Name}, Contacts) ->
    case dict:find(Name, Contacts) of
        error -> stop;
        {ok, Value} -> {reply, Value}
    end;
handle_read(list_all, Contacts) ->
    List = dict:to_list(Contacts),
    case List of 
        [] -> throw(list_contacts_empty);
        L -> {reply, lists:map(fun({_, C}) -> C end, L)} 
    end.   
    


