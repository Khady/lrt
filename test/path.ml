open Dynt

let pprint p =
  Format.(printf "%a\n%!" Path.print p)

let tprint x =
  Ttype.stype_of_ttype x
  |> Format.(fprintf std_formatter "%a\n%!" Stype.print_stype)

let vprint t v =
  Format.(printf "%a\n%!" (Print.print ~t) v)

let dprint dyn =
  let open Ttype in
  let Dyn (t,v) = dyn in
  vprint t v

type t =
  | A of {b: (int array list * string)}
[@@deriving t]

let value = A { b = [[|0;1|];[|0;1;2|];[|0|]], "string" }

let%expect_test _ =
  tprint t; vprint t value;
  let p1 = Path.Internal.([Constructor ("A",1)]) |> Obj.magic in pprint p1;
  let t', value' = Path.extract ~t:t p1 value in vprint t' value';
  let p2 = Path.Internal.(p1 @ [Field "b"]) |> Obj.magic in pprint p2;
  let t', value' = Path.extract ~t p2 value in vprint t' value';
  let p3 = Path.Internal.(p2 @ [Tuple_nth 0]) |> Obj.magic in pprint p3;
  let t', value' = Path.extract ~t p3 value in vprint t' value';
  let p4 = Path.Internal.(p3 @ [List_nth 1]) |> Obj.magic in pprint p4;
  let t', value' = Path.extract ~t p4 value in vprint t' value';
  let p5 = Path.Internal.(p4 @ [Array_nth 2]) |> Obj.magic in pprint p5;
  let t', value' = Path.extract ~t p5 value in vprint t' value';
  [%expect {|
    (t =
       | A of
        (t.A =
           {
             b: (int array list * string);
           }))
    A{b = ([[|0; 1|]; [|0; 1; 2|]; [|0|]], "string")}
    .A
    {b = ([[|0; 1|]; [|0; 1; 2|]; [|0|]], "string")}
    .A.b
    ([[|0; 1|]; [|0; 1; 2|]; [|0|]], "string")
    .A.b.(0)
    [[|0; 1|]; [|0; 1; 2|]; [|0|]]
    .A.b.(0).[1]
    [|0; 1; 2|]
    .A.b.(0).[1].[|2|]
    2 |}]

module B0 = struct
  open Path
  open Ttype

  type ('a,'b) t =
    { root : 'a ttype
    ; target : 'b ttype
    ; steps: Internal.step list}

  let r t : ('a, 'a) t =
    { root = t; target = t; steps = []}

  let l nth (p : ('a,'b list) t) : ('a, 'b) t =
    match stype_of_ttype p.target with
    | DT_list s -> { root = p.root
                   ; target = Obj.magic s
                   ; steps = List_nth nth :: p.steps }
    | _ -> assert false

  let a nth (p : ('a,'b array) t) : ('a, 'b) t =
    match stype_of_ttype p.target with
    | DT_array s -> { root = p.root
                    ; target = Obj.magic s
                    ; steps = Array_nth nth :: p.steps }
    | _ -> assert false

  let e (p : ('a, 'b) t) : ('a,'b, _) Path.t =
    Obj.magic (List.rev p.steps)

end

type ial = int array list [@@deriving t]
let ial = [[||];[|1|];[|2;0;1|]]

let%expect_test _ =
  let p = B0.(r ial_t |> l 2 |> a 0 |> e) in pprint p;
  let t', value' = Path.extract ~t:ial_t p ial in vprint t' value';
  [%expect {|
    .[2].[|0|]
    2 |}]

module B1 = struct
  open Path
  open Ttype

  type steps = Internal.step list
  type 'a t = Path : {steps: steps; root: 'a ttype; target: 'b ttype} -> 'a t

  let root t : 'a t =
    Path {steps=[];root=t;target=t}

  let constr name (Path p: 'a t) : 'a t option =
    match Xtypes.xtype_of_ttype p.target with
    | Sum s ->
      let i = Xtypes.Sum.lookup_constructor s name in
      if i < 0 then None else
        let Xtypes.Constructor c =
          Array.get (Xtypes.Sum.constructors s) i
        in Some (
          Path { p with target = Xtypes.Constructor.ttype c
                      ; steps = Internal.Constructor (name, -1) :: p.steps })
    | _ -> None

  let field name (Path p: 'a t) : 'a t option =
    match Xtypes.xtype_of_ttype p.target with
    | Record r -> begin
      match Xtypes.Record.find_field r name with
      | Some (Xtypes.Field f) -> Some (
          Path { p with target = Xtypes.RecordField.ttype f
                      ; steps = Internal.Field name :: p.steps })
      | None -> None
    end
    | _ -> None

  let tuple n (Path p: 'a t) : 'a t option =
    match Xtypes.xtype_of_ttype p.target with
    | Tuple r -> begin
      let fields = Xtypes.Record.fields r in
      if List.length fields > n then
        let Xtypes.Field f = List.nth fields n in
        Some ( Path { p with target = Xtypes.RecordField.ttype f
                           ; steps = Internal.Tuple_nth n :: p.steps })
      else None
    end
    | _ -> None

  let list nth (Path p: 'a t) : 'a t option =
    match Xtypes.xtype_of_ttype p.target with
    | List (t,_) -> Some (
          Path { p with target = t
                      ; steps = Internal.List_nth nth :: p.steps })
    | _ -> None

  let array nth (Path p: 'a t) : 'a t option =
    match Xtypes.xtype_of_ttype p.target with
    | Array (t,_) -> Some (
          Path { p with target = t
                      ; steps = Internal.Array_nth nth :: p.steps })
    | _ -> None

  let get (Path p : 'a t) (x : 'a) : dynamic option =
    match Path.extract ~t:p.root (Obj.magic (List.rev p.steps)) x with
    | _, value -> Some (Dyn (p.target, value))
    | exception (Failure _) -> None

  let close (target: 'b ttype) (Path p : 'a t)
    : ('a, 'b, _) Path.t option =
    match ttypes_equality_modulo_props target p.target with
    | Some _ -> Some (Obj.magic (List.rev p.steps))
    | None -> None

  let (|>>) x f =
    match x with
    | None -> None
    | Some y -> f y

  let (>>) x f = f (root x)
  let (||>) x t = x |>> close t

end

let xprint p value =
  match p with
  | Some p -> begin match B1.get p value with
      | None -> print_endline "Invalid value"
      | Some dyn -> dprint dyn
    end
  | None -> print_endline "Invalid path"

type sum =
  | A of int
  | B of (int * int)
[@@deriving t]

let a = A 42
let b = B (41,0)

let%expect_test _ =
  xprint B1.(sum_t >> constr "A") a ;
  xprint B1.(sum_t >> constr "B") b ;
  [%expect {|
    42
    (41, 0) |}]

type record =
  { a: int
  ; b: int * int
  ; c: sum
  ; d: string list
  ; e: bool array
  }
[@@deriving t]

let record =
  { a = 42
  ; b = (41, 0)
  ; c = B (7, 13)
  ; d = ["dynamic"; "types"; "are"; "cool"]
  ; e = [|false;true;false|]
  }

let%expect_test _ =
  xprint B1.(record_t >> field "a") record ;
  xprint B1.(record_t >> field "b") record ;
  xprint B1.(record_t >> field "c" |>> constr "B") record ;
  xprint B1.(record_t >> field "b" |>> tuple 0) record ;
  xprint B1.(record_t >> field "d" |>> list 1) record ;
  xprint B1.(record_t >> field "e" |>> array 2) record ;
  let () =
    match B1.(record_t >> field "e" |>> array 2 ||> bool_t) with
    | Some p -> pprint p
    | None -> print_endline "Invalid Path"
  in
  [%expect {|
    42
    (41, 0)
    (7, 13)
    41
    "types"
    false
    .e.[|2|] |}]

module P =  struct

  let print_list ppf ~opn ~cls ~sep print_el l =
    let rec f = function
      | [] -> ()
      | hd :: [] -> Format.fprintf ppf "%a" print_el hd
      | hd :: tl ->
        Format.fprintf ppf "%a" print_el hd ;
        Format.fprintf ppf "%s" sep;
        f tl
    in
    Format.fprintf ppf "%s" opn;
    f l;
    Format.fprintf ppf "%s" cls

  type ('a,'b) step = ('a,'b) lens * meta

  and ('a,'b) lens =
    { get : 'a -> 'b option
    ; set : 'a -> 'b -> 'a option
    }

  and meta = (* private *)
    | Field of {name: string}
    | Constructor of {name: string; arg: constructor_argument}
    | Tuple of {nth: int; arity: int}
    | List of {nth: int}
    | Array of {nth: int}

  and constructor_argument =
    | Regular of {nth: int; arity: int}
    | Inline of {field: string}

  type (_,_) t =
    | (::) : ('a,'b) step * ('b,'c) t -> ('a,'c) t
    | [] : ('a, 'a) t

  let rec print_step ppf = function
    | Field {name} -> Format.fprintf ppf "%s" name
    | Constructor {name; arg = Regular {nth;arity}} ->
      Format.fprintf ppf "%s %a" name print_step (Tuple {nth;arity})
    | Constructor {name; arg = Inline {field}} ->
      Format.fprintf ppf "%s %a" name print_step (Field {name=field})
    | Tuple {nth; arity}->
      let a = Array.make arity "_" in
      Array.set a nth "[]";
      if arity > 1 then Format.fprintf ppf "(" ;
      print_list ppf ~opn:"" ~cls:"" ~sep:","
        (fun ppf s -> Format.fprintf ppf "%s" s) (Array.to_list a);
      if arity > 1 then Format.fprintf ppf ")";
    | List {nth} -> Format.fprintf ppf "[%i]" nth
    | Array {nth} -> Format.fprintf ppf "[|%i|]" nth

  let meta_list t =
    let rec fold : type a b.
      meta list -> (a,b) t -> meta list =
      fun acc -> function
        | [] -> List.rev acc
        | (_, hd) :: tl -> fold (hd :: acc) tl
    in
    fold [] t

  let print ppf t =
    print_list ppf ~opn:"[%path? [" ~cls:"]]" ~sep:"; "
      print_step (meta_list t)

  let lens (t : ('a,'b) t) : ('a,'b) lens =
    let root : ('a,'a) lens =
      let set _a b = Some b
      and get a = Some a
      in { set; get }
    in
    let rec fold : type a b c.
      (a,b) lens -> (b,c) t -> (a,c) lens =
      fun acc -> function
        | [] -> acc
        | (hd, _) :: tl ->
          let get a =
            match acc.get a with
            | None -> None
            | Some x -> hd.get x
          in
          let set a c =
            match acc.get a with
            | None -> None
            | Some b ->
              match hd.set b c with
              | None -> None
              | Some b -> acc.set a b
          in
          fold {get; set} tl
    in fold root t

end

type y = Int of int | Bool of bool | Pair of int * string
type z = Y of {y1: y; y2: y; y3: y}
type x = { x1 : z; x2 : z}
type r = x * y
type s = r list
type f = s array
type e = { e : f }

let p = [%path? [e; [|50|]; [1]; ([],_); x1; Y y2; Pair (_,[])]]

let%expect_test _ =
  Format.printf "%a\n%!" P.print p;
  [%expect {| [%path? [e; [|50|]; [1]; ([],_); x1; Y ([],_,_); Pair (_,[])]] |}]

let value = [| ["hey"; "hi"] |]
let p2 = [%path? [[|0|]; [1]]]
let l2 = P.lens p2

let assert_some = function
  | Some x -> x
  | None -> assert false

let%expect_test _ =
  print_endline (l2.get value |> assert_some);
  print_endline (l2.set value "salut" |> assert_some |> l2.get |> assert_some);
  [%expect {|
    hi
    salut |}]
