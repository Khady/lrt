(** Runtime components of [\[@@deriving t\]] and [\[%path? .\]]. *)
(**/**)

module Types = struct
  (** Runtime for building types *)

  open Dynt_core.Stype
  open Dynt_core.Ttype
  open Dynt_core.Stype.Internal

  type 'a lazy_t = 'a Lazy.t
  type nonrec 'a ttype = 'a ttype
  type nonrec node = node

  let ttype_of_stype (type a) (s : stype) = (Obj.magic s : a ttype)

  let substitute = substitute
  let stype_of_ttype = stype_of_ttype
  let create_node = create_node
  let set_node_record = set_node_record
  let set_node_variant = set_node_variant

  let rev_map2 = List.rev_map2
  let force = Lazy.force

  let record_representation (l: stype list) : record_repr =
    let p = types_equality_modulo_props (
        stype_of_ttype Dynt_core.Std.float_t) in
    if List.for_all p l then Record_float else Record_regular

  module Set = Set.Make(String)
  let abstract_names = ref Set.empty

  exception Non_unique_abstract_name of string

  let register_abstract_name s =
    if Set.mem s !abstract_names then raise (Non_unique_abstract_name s);
    abstract_names := Set.add s !abstract_names
end

module Path = struct
  (** Runtime for building paths *)

  (* Make sure that nobody masks the things we use *)
  module Array = Array
  module List = List
  type nonrec 'a option = 'a option =
    | None
    | Some of 'a

  (* Set nth element in a list *)
  let set_nth l nth x =
    let rec f acc l nth =
      match nth, l with
      | 0, _hd :: tl -> List.rev_append acc (x :: tl)
      | _i, [] -> raise (Failure "nth")
      | i, hd :: tl -> f (hd :: acc) tl (i-1)
    in
    if nth < 0 then raise (Invalid_argument "List.nth")
    else f [] l nth

  let set_nth_opt l nth x =
    match set_nth l nth x with
    | x -> Some x
    | exception _ -> None

  include Dynt_core.Path
  include Internal [@@ocaml.warning "-3"]

end