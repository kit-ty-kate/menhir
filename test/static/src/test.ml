(* This script produces the file [dune.auto], which describes the tests we
   would like dune to execute. *)

(* Note: the contents of the .conflicts and .automaton files are not tested. *)

(* -------------------------------------------------------------------------- *)

open Sys
open Array
open List
open Printf
open Auxiliary

let up =
  Filename.parent_dir_name
let (/) =
  Filename.concat
let (//) directory filenames =
  map (fun filename -> directory/filename) filenames

(* -------------------------------------------------------------------------- *)

(* Settings. *)

let extra : string list ref =
  ref []

let usage =
  sprintf "Usage: %s\n" argv.(0)

let spec = Arg.align [
  "--extra-flags",     Arg.String (fun flag -> extra := flag :: !extra),
                       "<string> specify extra flags for Menhir";
]

let () =
  Arg.parse spec (fun _ -> ()) usage

let extra : string list =
  rev !extra

(* -------------------------------------------------------------------------- *)

(* Paths. *)

let good =
  up / "good"

let bad =
  up / "bad"

(* -------------------------------------------------------------------------- *)

(* Test files and groups of test files. *)

let id basenames =
  (* A name for a nonempty group of test files. *)
  hd basenames

let mly basename =
  basename ^ ".mly"

let mlys =
  map mly

(* -------------------------------------------------------------------------- *)

(* Test inputs and outputs. *)

(* A test input is a list of basenames, without the .mly extension.
   These files must be passed together to menhir. *)

type input =
  | NegativeTest of filename list
  | PositiveTest of filename list

type inputs = input list

(* -------------------------------------------------------------------------- *)

(* An S-expression printer. *)

type sexp =
  | A of string
  | L of sexp list
  | Lnewline of sexp list

let atom sexp =
  A sexp

let atoms =
  map atom

let rec print ppf = function
  | A s ->
      Format.pp_print_string ppf s
  | L l ->
      Format.fprintf ppf "@[<2>(%a)@]"
        (Format.pp_print_list ~pp_sep:Format.pp_print_space print) l
  | Lnewline l ->
      Format.fprintf ppf "@[<v 2>(%a)@]"
        (Format.pp_print_list ~pp_sep:Format.pp_print_space print) l

let print sexp =
  Format.printf "@[<v>%a@,@]" print sexp;
  Format.print_newline()

(* -------------------------------------------------------------------------- *)

(* Constructing a standard [make]-like rule. *)

let rule (target : string) (deps : string list) (action : sexp) =
  L[A"rule";
    L[A"target"; A target];
    L(A"deps" :: atoms deps);
    L[A"action"; action]
  ]

(* Constructing a phony rule, that is, a rule whose target is an alias. *)

let phony (alias : string) (action : sexp) =
  L[A"rule";
    L[A"alias"; A alias];
    L[A"action"; action]
  ]

(* Constructing a diff action. *)

let diff (expected : string) (actual : string) =
  L[A"diff"; A expected; A actual]

(* Redirecting the output channels of an action towards its target. *)

let targeted action =
  L[A"with-outputs-to"; A"%{target}"; action]

(* Changing the working directory of an action. *)

let chdir directory action =
  L[A"chdir"; A directory; action]

(* Expressing the fact that an action is expected to fail. *)

let expecting_failure action =
  L[A"with-accepted-exit-codes"; L[A"not"; A"0"]; action]

let possibly_expecting_failure positive action =
  if positive then action else expecting_failure action

(* -------------------------------------------------------------------------- *)

(* Calling conventions for Menhir. *)

(* A --base option is needed for groups of several files. *)

let base basenames =
  if length basenames > 1 then
    let id = id basenames in
    [A"--base"; A id]
  else
    []

(* The extra flags passed to Menhir are those found in a local .flags file,
   if there is one, plus those passed to us via --extra-flags. *)

let extra source id =
  let flags_file = source / id ^ ".flags" in
  if file_exists flags_file then
    A(sprintf "%%{read-lines:%s}" flags_file) :: atoms extra
  else
    atoms extra

(* The Menhir command. *)

(* This command is meant to be used inside a rule. *)

let menhir base flags =
  L(A"run" :: A"menhir" :: base @ flags @ [A"%{deps}"])

(* Constructing (and printing) a pair of rules to run Menhir and compare its
   output against an expected-output file.

   [id]         name of the phony target
   [positive]   positive or negative test?
   [source]     directory where the .mly files reside
   [basenames]  base names of the .mly files
   [output]     name of the output file
   [expected]   name of the expected-output file
   [flags]      flags for Menhir

 *)

let run_and_compare id positive source basenames output expected flags =
  (* Run Menhir. *)
  print (rule
    output
    (source // mlys basenames)
    (targeted (chdir source (
      possibly_expecting_failure positive (
        menhir (base basenames) flags
  )))));
  (* Check that the output coincides with what was expected. *)
  print (phony id (
    diff (source/expected) output
  ))

(* -------------------------------------------------------------------------- *)

(* Running a negative test. *)

(* This test takes place in the directory [bad]. *)

(* The file %.flags   (if it exists) stores flags for Menhir.
   The file %.result     stores the output of menhir.
   The file %.expected     stores its expected output. *)

let process_negative_test basenames : unit =
  (* Run menhir. *)
  let source = bad in
  let id = id basenames in
  let output = id ^ ".result" in
  let expected = id ^ ".expected" in
  let flags = extra source id in
  run_and_compare id false source basenames output expected flags

(* -------------------------------------------------------------------------- *)

(* Running a positive test. *)

(* This test takes place in the directory [good]. *)

(* The file %.flags   (if it exists) stores flags for Menhir.
   The file %.opp.out stores the output of menhir --only-preprocess.
   The file %.opp.exp stores its expected output.
   The file %.out     stores the output of menhir.
   The file %.exp     stores its expected output. *)

let process_positive_test basenames : unit =
  let source = good in
  let id = id basenames in
  let flags = extra source id in
  (* Run menhir --only-preprocess. *)
  let output = id ^ ".opp.out" in
  let expected = id ^ ".opp.exp" in
  run_and_compare id true source basenames output expected
    (A"--only-preprocess" :: flags);
  (* Run menhir. *)
  let output = id ^ ".out" in
  let expected = id ^ ".exp" in
  run_and_compare id true source basenames output expected
    (atoms ["--explain"; "-lg"; "2"; "-la"; "2"; "-lc"; "2"] @ flags)

(* -------------------------------------------------------------------------- *)

(* Running a test. *)

let process input =
  match input with
  | NegativeTest basenames ->
      process_negative_test basenames
  | PositiveTest basenames ->
      process_positive_test basenames

let id input =
  match input with
  | NegativeTest basenames
  | PositiveTest basenames ->
      id basenames

(* -------------------------------------------------------------------------- *)

(* [run] runs a bunch of tests in parallel. *)

let run (inputs : inputs) =
  iter process inputs;
  let ids = map id inputs in
  let ids = sort_uniq compare ids in
  print
    (L[A"alias";
       L[A"name"; A"test"];
       Lnewline(A"deps" :: map (fun id -> L[A"alias"; A id]) ids)])

(* -------------------------------------------------------------------------- *)

(* Main. *)

(* Menhir can accept several .mly files at once. By convention, if several
   files have the same name up to a numeric suffix, then they belong in a
   single group and should be fed together to Menhir. *)

let inputs directory : filename list list =
     readdir directory
  |> to_list
  |> filter (has_suffix ".mly")
  |> map Filename.chop_extension
  |> sort compare
  |> groups equal_up_to_numeric_suffix

let positive : inputs =
     inputs good
  |> map (fun basenames -> PositiveTest basenames)

let negative : inputs =
     inputs bad
  |> map (fun basenames -> NegativeTest basenames)

let inputs =
  positive @ negative

let () =
  print_endline
    ";; This file has been auto-generated. Please do not edit it.\n\
     ;; Instead, edit [test.ml] and run [make depend].\n"

let () =
  run inputs
