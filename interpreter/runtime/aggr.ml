open Types
open Value

type field =
  | ValField of value ref
  | PackField of Pack.pack_size * int ref

type aggr =
  | Struct of type_addr * Rtt.t * field list
  | Array of type_addr * Rtt.t * field list
type t = aggr

type ref_ += AggrRef of aggr


let gap sz = 32 - 8 * Pack.packed_size sz
let wrap sz i = Int32.(to_int (logand i (shift_right_logical (-1l) (gap sz))))
let extend_u sz i = Int32.of_int i
let extend_s sz i = Int32.(shift_right (shift_left (of_int i) (gap sz)) (gap sz))

let alloc_field ft v =
  let FieldT (_mut, st) = ft in
  match st, v with
  | ValStorageT _, v -> ValField (ref v)
  | PackStorageT sz, Num (I32 i) -> PackField (sz, ref (wrap sz i))
  | _, _ -> failwith "alloc_field"

let write_field fld v =
  match fld, v with
  | ValField vr, v -> vr := v
  | PackField (sz, ir), Num (I32 i) -> ir := wrap sz i
  | _, _ -> failwith "write_field"

let read_field fld exto =
  match fld, exto with
  | ValField vr, None -> !vr
  | PackField (sz, ir), Some Pack.ZX -> Num (I32 (extend_u sz !ir))
  | PackField (sz, ir), Some Pack.SX -> Num (I32 (extend_s sz !ir))
  | _, _ -> failwith "read_field"


let alloc_struct x rtt vs =
  let StructT fts = as_struct_str_type (expand_ctx_type (def_of x)) in
  Struct (x, rtt, List.map2 alloc_field fts vs)

let alloc_array x rtt vs =
  let ArrayT ft = as_array_str_type (expand_ctx_type (def_of x)) in
  Array (x, rtt, List.map (alloc_field ft) vs)


let type_inst_of = function
  | Struct (x, _, _) -> x
  | Array (x, _, _) -> x

let struct_type_of d = as_struct_str_type (expand_ctx_type (def_of (type_inst_of d)))
let array_type_of d = as_array_str_type (expand_ctx_type (def_of (type_inst_of d)))

let read_rtt = function
  | Struct (_, rtt, _) -> rtt
  | Array (_, rtt, _) -> rtt


let () =
  let type_of_ref' = !Value.type_of_ref' in
  Value.type_of_ref' := function
    | AggrRef d -> DefHT (DynX (type_inst_of d))
    | r -> type_of_ref' r

let string_of_field = function
  | ValField vr -> string_of_value !vr
  | PackField (_, ir) -> string_of_int !ir

let string_of_fields fs =
  let fs', ell =
    if List.length fs > 5
    then Lib.List.take 5 fs, ["..."]
    else fs, []
  in String.concat " " (List.map string_of_field fs' @ ell)

let rec_for inner f x =
  inner := true;
  try let y = f x in inner := false; y
  with exn -> inner := false; raise exn

let () =
  let string_of_ref' = !Value.string_of_ref' in
  let inner = ref false in
  Value.string_of_ref' := function
    | AggrRef _ when !inner -> "..."
    | AggrRef (Struct (_, _, fs)) ->
      "(struct " ^ rec_for inner string_of_fields fs ^ ")"
    | AggrRef (Array (_, _, fs)) ->
      "(array " ^ rec_for inner string_of_fields fs ^ ")"
    | r -> string_of_ref' r