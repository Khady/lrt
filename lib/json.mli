(******************************************************************************)
(*  Copyright (C) 2018 by LexiFi.                                             *)
(*                                                                            *)
(*  This source file is released under the terms of the MIT license as part   *)
(*  of the dynt package. Details can be found in the attached LICENSE file.   *)
(******************************************************************************)

(** Json compatible representation of values. *)

(** {3 Representation of JSON trees} *)

type number = I of int | F of float

type value =
  | Null
  | Bool of bool
  | Number of number
  | String of string
  | Array of value list
  | Object of (string * value) list
[@@deriving t]

(** Notes:
    - The [String] payload is either Latin1-encoded or utf8-encoded,
      depending on the [utf8] flag passed to [encode/decode].
      When not in utf8 mode, a code point outside the range of that character set will
      be encoded in a special (undocumented) way.
*)

(** {3 Mapping between JSON trees and their textual representation.} *)

val encode : ?utf8:bool -> value -> string
(** Encode JSON tree into a compact JSON text (single line,  etc). *)

val decode : ?utf8:bool -> ?filename:string -> string -> value
(** Parse a JSON text into JSON tree.  Report parse errors using
    the [Failure] exception. The optional [filename] argument
    is used to report locations in error messages. *)

val to_pretty_string : value -> string
(** Prints a JSON tree into human-friendly text (multi-line, indentation).
    The output is NOT a parsable json string.
*)

(** Context storing serialization variations directives.

    Variations:
    - to_json_field: how to translate a json field name to an mlfi record field.
*)
type ctx

val ctx : ?to_json_field:(string -> string) -> unit -> ctx

(** {3 Typeful generic mapping between JSON trees and OCaml values.} *)

(** TODO: update docs *)

(**
   [to_json x] maps an OCaml value to a JSON tree representing the same
   information.  The mapping is driven by the type of [x] and the
   default behavior (which can be overridden) is defined below.

   Basic types:
   {[
   - 1          ---> 1
   - 1.         ---> 1.
   - ()         ---> {}
   - true/false ---> true/false
   - "abc"      ---> "abc"
   - 2001-01-01 ---> "2001-01-01"
   ]}

   List/array/tuple types:
   {[
   - [x; y]   ---> [x', y']
   - [|x; y|] ---> [x', y']
   - (x, y)   ---> [x', y']
   ]}

   Record types:
   {[
   - {l1 = x; l2 = y}    ---> {"l1": x', "l2": y'}
   - {l1 = x; l2 = None} ---> {"l1": x'}
   ]}

   Sum types:
   {[
   - A                  ---> {"type": "A"}
   - B x                ---> {"type": "B", "val": [x'] }
   - C (x, y)           ---> {"type": "C", "val": [x', y'] }
   - D {l1 = x; l2 = y} ---> {"type": "D", "l1": x', "l2": y'}
   ]}

   Option types:
   {[
   - Some x ---> x'
   - None   ---> null (when not in record)
   ]}

   Nested option types!
   {[
   - Some (Some x) ---> {"type": "Some", "val": x'}
   - Some None     ---> {"type": "Some"}
   - None          ---> {"type": "None"}
   ]}

   Lazy types:
   {[
   - lazy x ---> x'
     (x is forced upon jsonification; de-jsonification is lazy)
   ]}

   String Maps ('a Mlfi_sets_maps.StringMap.t)
     are mapped to objects, e.g.
   {[
   - {"a" -> 1; "b" -> 2}                 ---> {"a": 1, "b": 2}
   - {"foo" -> "hello"; "bar" -> "world"} ---> {"foo": "hello", "bar": "world"}
   ]}

   Special cases:
   {[
   - (x : Variant.t)  ---->  <textual representation of x, in OCaml syntax>
   - (x : Json.value) ---->  x
   ]}


   Notes:

   - Function types and object types are not supported.

   - Upon parsing, extra fields in objects are accepted and ignored
     (including when parsing a sum type or unit).

   - Special float values (nan, infinity) are not supported (but
     not explicitly checked).

   - TODO?: special case when all constructors are empty (mapped to strings).

   - TODO: support some type properties (default value, etc).

*)

(** Reverse mapping.  If [to_json ~t x] succeeds, the property
    [of_json ~t (to_json ~t x) = x] is expected to hold
    (except corner cases such as unchecked special float values,
    and assuming that custom converters behaves properly).
*)

type 'a conv = {to_json: 'a -> value; of_json: value -> 'a}

val conv : ?ctx:ctx -> 'a Ttype.t -> 'a conv

(** {3 Custom mapping for specific types} *)

(* TODO: support passing local custom conversions to to_json/of_json. *)

(** [register_conversion] registers a global custom mapping between
    OCaml values and JSON trees for a specific closed *abstract* type.

    TODO: Bring this documentation up to date. Especially, we support
    non-abstract things now.

    It is not allowed to use [null] in the JSON representation of
    values, at least if the type is used under the option type
    constructor ([null] is reserved for representing the
    [None] case).
*)

module Matcher : Matcher.S with type 'a data := 'a conv

(* TODO: move somewhere else *)
val of_get_params : ?utf8:bool -> (string * string) list -> value
val to_get_params : ?utf8:bool -> value -> (string * string) list

module Access : sig
  val is_null : value -> bool
  val to_string : value -> string
  val to_int : value -> int
  val to_float : value -> float
  val to_list : value -> value list
  val get_field : string -> value -> value
  val string_field : string -> value -> string
  val int_field : string -> value -> int
  val float_field : string -> value -> float
  val list_field : string -> value -> value list
  val object_field : string -> value -> value
end
