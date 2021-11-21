open StackLangBasics
open Reg.Set

let add_registers accu v =
  match v with
  | VTag _
  | VUnit
    -> accu
  | VReg r ->
      add r accu

let occurs1 r v =
  match v with
  | VTag _
  | VUnit ->
      false
  | VReg r' ->
      r = r'

let registers vs =
  List.fold_left add_registers empty vs

let rec occurs r vs =
  match vs with
  | [] ->
      false
  | v :: vs ->
      occurs1 r v || occurs r vs
