module type C0 = sig
  include Unify.T0
  type res
  val f: t -> res
end

module type C1 = sig
  include Unify.T1
  type res
  val f: 'a Ttype.t -> 'a t -> res
end

module type C2 = sig
  include Unify.T2
  type res
  val f: 'a Ttype.t -> 'b Ttype.t -> ('a, 'b) t -> res
end

type 'a candidate =
  | T0 of (module C0 with type res = 'a)
  | T1 of (module C1 with type res = 'a)
  | T2 of (module C2 with type res = 'a)

type 'a compiled = 'a candidate list

type 'a t = 'a candidate list * ('a compiled Lazy.t)

module Step : sig
  type t
  val compare : t -> t -> int
  val of_stype : modulo_props: bool -> Stype.t -> t * Stype.t list
end = struct
  type base = | Int | Float | String | Array | List | Option | Arrow
  type t =
    | Base of base
    | Tuple of int
    | Props of Stype.properties
    | Abstract of int * string (* arity, name *)
    | Record of string * Stype.record_repr * ( string * Stype.properties) list

  let map_record name flds repr =
    let flds, stypes = List.fold_left (fun (flds, stypes) (name, prop, s) ->
        ((name, prop) :: flds, s :: stypes)) ([], []) flds
    in (name, repr, flds), stypes

  let rec of_stype : modulo_props: bool -> Stype.t -> t * Stype.t list =
    fun ~modulo_props -> function
      | DT_int -> Base Int, []
      | DT_float -> Base Float, []
      | DT_string -> Base String, []
      | DT_list a -> Base List, [a]
      | DT_array a -> Base Array, [a]
      | DT_option a -> Base Option, [a]
      | DT_arrow (_, a, b) -> Base Arrow, [a; b]
      | DT_prop (_, s) when modulo_props -> of_stype ~modulo_props s
      | DT_prop (p, s) -> Props p, [s]
      | DT_tuple l -> Tuple (List.length l), l
      | DT_abstract (name, args) ->
        Abstract (List.length args, name), args
      | DT_node { rec_descr = DT_record {record_fields; record_repr}
                ; rec_name; _ } ->
        let (name, repr, flds), types =
          map_record rec_name record_fields record_repr
        in
        (* TODO: verify, that rec_args are indeed irrelevant *)
        (* TODO: The same record can be defined twice in different modules
           and pass this comparison. Solution: insert unique ids on
           [@@deriving t]. Or check what the existing rec_uid is doing.
           This would speed up comparison quite a bit, ie. only args need
           to be compared *)
        Record (name, repr, flds), types
      | DT_node _ -> failwith "TODO: handle variants"
      | DT_object _ -> failwith "TODO: handle objects"
      | DT_var _i -> failwith "TODO: handle variables"

  let compare = compare
end

module Trie : sig
  type t
  type key = Stype.t
  val empty : t
  val add : modulo_props:bool -> key -> t -> t
  (* TODO: modulo_props might be part of t *)
  val mem : modulo_props:bool -> key -> t -> bool
end = struct
  module Map = Map.Make(Step)

  type key = Stype.t

  type t = node Map.t
  and node =
  | Inner of t list
  | Leave

  let empty = Map.empty

  let rec add ~modulo_props stype t =
    let step, stypes = Step.of_stype ~modulo_props stype in
    let node = match Map.find_opt step t with
    | None ->
      begin match stypes with
        | [] -> Leave
        | stypes -> Inner (
            List.map (fun s -> add ~modulo_props s Map.empty) stypes)
      end
    | Some Leave -> raise (Invalid_argument "type already registered")
    | Some (Inner l) -> Inner (
        List.map2 (fun s m -> add ~modulo_props s m) stypes l)
    in
    Map.add step node t

  let rec mem ~modulo_props stype t =
    let step, stypes = Step.of_stype ~modulo_props stype in
    match Map.find_opt step t with
    | None -> false
    | Some Leave when stypes = [] -> true
    | Some Leave -> false
    | Some (Inner l) ->
      List.for_all2 (fun s t -> mem ~modulo_props s t) stypes l
end

let%test _ =
  let modulo_props = true in
  let add typ = Trie.add ~modulo_props (Ttype.to_stype typ) in
  let mem typ = Trie.mem ~modulo_props (Ttype.to_stype typ) in
  let open Std in
  let t = Trie.empty
          |> add (list_t int_t)
          |> add (option_t string_t)
          |> add (int_t)
  in
  List.for_all (fun x -> x)
    [ mem (list_t int_t) t
    ; mem (option_t string_t) t
    ; not (mem (option_t int_t) t)
    ]

let compile : type res. res candidate list -> res t =
  fun candidates -> (candidates, lazy (List.rev candidates))
(* This implies oldest added is tried first. What do we want? *)
(* TODO: Build some efficient data structure. *)

let empty : 'a t = [], lazy []

let add (type t res) ~(t: t Ttype.t) ~(f: t -> res) (lst, _) =
  T0 (module struct
    type nonrec t = t [@@deriving t]
    type nonrec res = res
    let f = f end) :: lst
  |> compile

let add0 (type a) (module C : C0 with type res = a) (lst, _) =
  T0 (module C : C0 with type res = a) :: lst
  |> compile

let add1 (type a) (module C : C1 with type res = a) (lst, _) =
  T1 (module C : C1 with type res = a) :: lst
  |> compile

let add2 (type a) (module C : C2 with type res = a) (lst, _) =
  T2 (module C : C2 with type res = a) :: lst
  |> compile

let apply' : type res. res t -> Ttype.dynamic -> res =
  fun (_, lazy matcher) (Ttype.Dyn (t,x)) ->
    let (module B) = Unify.t0 t
    and (module P) = Unify.init ~modulo_props:false in
    let rec loop = function
      | [] -> raise Not_found
      | T0 (module A : C0 with type res = res) :: tl ->
        begin try
            let module U = Unify.U0 (P) (A) (B) in
            let TypEq.Eq = U.eq in A.f x
          with Unify.Not_unifiable -> loop tl end
      | T1 (module A : C1 with type res = res) :: tl ->
        begin try
            let module U = Unify.U1 (P) (A) (B) in
            let TypEq.Eq = U.eq in A.f U.a_t x
          with Unify.Not_unifiable -> loop tl end
      | T2 (module A : C2 with type res = res) :: tl ->
        begin try
            let module U = Unify.U2 (P) (A) (B) in
            let TypEq.Eq = U.eq in A.f U.a_t U.b_t x
          with Unify.Not_unifiable -> loop tl end
    in loop matcher

let apply matcher ~t x = apply' matcher (Ttype.Dyn (t, x))
