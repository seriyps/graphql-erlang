-module(gql_schema_validate).

-include("gql_schema.hrl").

-export([x/0]).

-spec x() -> ok.
x() ->
    Objects = gql_schema:all(),
    [x(Obj) || Obj <- Objects],
    ok.
    
x(#scalar_type {}) -> ok;
x(#root_schema {} = X) -> root_schema(X);
x(#object_type {} = X) -> object_type(X);
x(#enum_type {} = X) -> enum_type(X);
x(#interface_type {} = X) -> interface_type(X);
x(#union_type {} = X) -> union_type(X);
x(#input_object_type {} = X) -> input_object_type(X).

enum_type(#enum_type {}) ->
    %% TODO: Validate values
    ok.

input_object_type(#input_object_type { fields = FS }) ->
    all(fun schema_arg/1, maps:to_list(FS)),
    ok.

union_type(#union_type { types = Types }) ->
    all(fun is_union_type/1, Types),
    ok.

interface_type(#interface_type { fields= FS }) ->
    all(fun schema_field/1, maps:to_list(FS)),
    ok.

object_type(#object_type {
	fields = FS,
	interfaces = IFaces} = Obj) ->
    all(fun is_interface/1, IFaces),
    all(fun(IF) -> implements(lookup(IF), Obj) end, IFaces),
    all(fun schema_field/1, maps:to_list(FS)),
    ok.

root_schema(#root_schema {
	query = Q,
	mutation = M,
	subscription = S,
	interfaces = IFaces }) ->
    undefined_object(Q),
    undefined_object(M),
    undefined_object(S),
    all(fun is_interface/1, IFaces),
    ok.
    
schema_field({_, #schema_field { ty = Ty, args = Args }}) ->
    all(fun schema_arg/1, maps:to_list(Args)),
    type(Ty),
    ok.

schema_arg({_, #schema_arg { ty = Ty }}) ->
    %% TODO: Default check!
    type(Ty),
    ok.

undefined_object(undefined) -> ok;
undefined_object(Obj) -> is_object(Obj).

implements(
	#interface_type { fields = IFFields } = IFace,
	#object_type { fields = ObjFields } = Obj) ->
    IL = lists:usort(maps:to_list(IFFields)),
    OL = lists:usort(maps:to_list(ObjFields)),
    case implements_field_check(IL, OL) of
        ok ->
            ok;
        {error, Reason} ->
            err({implements, IFace, Obj, Reason})
    end.
    
implements_field_check([], []) -> ok;
implements_field_check([], [_|OS]) -> implements_field_check([], OS);
implements_field_check([{K, IF} | IS], [{K, OF} | OS]) ->
    %% TODO: Arg check!
    case IF#schema_field.ty == OF#schema_field.ty of
        true ->
            implements_field_check(IS, OS);
        false ->
            {error, {type, K}}
    end;
implements_field_check([{IK, _} | IS], [{OK, _} | OS]) when IK > OK ->
    implements_field_check(IS, OS);
implements_field_check([{IK, _} | _], [{OK, _} | _]) when IK < OK ->
    {error, {not_found, IK}}.
    
is_interface(IFace) ->
    case lookup(IFace) of
        #interface_type{} -> ok;
        _ -> err({not_interface, IFace})
    end.

is_object(Obj) ->
    case lookup(Obj) of
        #object_type{} -> ok;
        _ -> err({not_object, Obj})
    end.

is_scalar(Obj) ->
    case lookup(Obj) of
        #scalar_type{} -> ok;
        _ -> err({not_scalar, Obj})
    end.

is_union_type(Obj) ->
    case lookup(Obj) of
        #object_type{} -> ok;
        _ -> err({not_union_type, Obj})
    end.

type({non_null, T}) -> type(T);
type([T]) -> type(T);
type({scalar, S}) -> scalar(S);
type(X) when is_binary(X) ->
    _ = lookup(X),
    ok.

scalar(string) -> ok;
scalar(id) -> ok;
scalar(float) -> ok;
scalar(int) -> ok;
scalar(bool) -> ok;
scalar(X) -> is_scalar(X).

all(_F, []) -> ok;
all(F, [E|Es]) ->
    ok = F(E),
    all(F, Es).

lookup(Key) ->
    case gql_schema:lookup(Key) of
        not_found -> err({schema_validation, {not_found, Key}});
        X -> X
    end.
    
err(Reason) -> exit({schema_validation, Reason}).