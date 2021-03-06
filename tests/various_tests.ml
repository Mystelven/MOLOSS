(*########################################################*)
(*          Fichier de tests divers & variés              *)
(*########################################################*)
module FO = Ast_fo
module M = Ast_modal
module C = Convertisseur
module PP = Pprinter
module U = Unix
module A = Array
module R = Random
module L = List
module Sy = Sys
module D = Direct
module S = String

module Sz3 = Solve.Solve(Smtz3.SMTz3)
module Sminisat = Solve.Solve(Smtminisat.Smtmini)

module Dummy =
struct
	let truc = 1
end

let pf = Printf.printf
let spf = Printf.sprintf

(*--------------------------------------------------------*)
(*            Génération aléatoire de formule             *)
(*--------------------------------------------------------*)
let variables = ["p";"q";"p2";"q2";"r";"r2";"s";"s2"]

let tire_var () =
begin
	R.self_init ();
	L.nth variables (R.int 4);
end


let rec tire_form n =
begin
	R.self_init ();
	match n with
	| 0 ->
	begin
		match R.int 2 with
		| 0 -> M.Atom (tire_var () )
		| _ -> M.Not (M.Atom (tire_var () ))
	end
	| n ->
	begin
		match (R.int 4)  with
		| 0 -> M.Conj (tire_form (n-1),tire_form (n-1))
		| 1 -> M.Dij (tire_form (n-1),tire_form (n-1))
		| 2 -> M.Boxe (tire_form(n-1))
		| _ -> M.Diamond (tire_form (n-1))
	end;

end


(*--------------------------------------------------------*)
(*                    Pour les axiomes                    *)
(*--------------------------------------------------------*)

let tire_ax () =
	let ax_a = [|"-M";"-4";"-B";"-5";"-CD"|] in
	let res = ref []
	in begin
		for i = 0 to 4 do
			if R.int 2 = 0 then
				res := ax_a.(i)::(!res);
		done;
		!res;
	end

let get_logic () =
	let argv = A.to_list (Sy.argv) in
	if L.mem "-T" argv then
		["-M"],"-T"
	else if L.mem "-B" argv then
		["-B"],"-B"
	else if L.mem "-4" argv then
		["-4"],"-4"
	else if L.mem "-5" argv then
		["-5"],"-5"
	else if L.mem "-CD" argv then
		["-CD"],"-CD"
	else if L.mem "-S4" argv then
		["-M";"-4"],"-S4"
	else if L.mem "-S5" argv then
		["-M";"-5"],"-S5"
	else if L.mem "-K" argv then
		[],"-K"
	else
		tire_ax (),"Undef"





(*--------------------------------------------------------*)
(*                Les tests en question                   *)
(*--------------------------------------------------------*)

let handle = function
| C.MeauvaisFormat s ->
	pf "Erreur : meauvais format \n %s \n" s
| C.FreeVDM (v1,v2,s) ->
	pf "Erreur : les variables %s et %s ne matchent pas : \n %s \n" v1 v2 s
| _ -> ()

let print_debug s =
begin
	print_string s;
	flush_all ();
end

let get_arg () =
	let nb =
		try int_of_string (Sy.argv.(1))
		with
		| _ ->
		begin
			pf "le premier argument est le nb d'essai \n";
			exit 1;
		end
	and n =
		try int_of_string (Sy.argv.(2))
		with
		| _ ->
		begin
			pf "le second argument est la profondeur max \n";
			exit 1;
		end
	in (nb,n)
   (*
let rec check_form = function
| M.Atom _ -> true
| M.Not f -> check_form f
| M.Conj (f1,f2) | M.Dij (f1,f2) | M.Impl (f1,f2) ->
	(check_form f1) && (check_form f2)
| M.Diamond f -> check_form f
| M.Boxe f -> match f with
	| M.Diamond _ -> false
	| _ -> check_form f
*)


let _ =
let nb,n = get_arg ()
and t0 = ref 0.
and t_sz3 = ref 0.
and t_direct = ref 0.
and t_msat = ref 0.
and t_minisat = ref 0.
and dt_sz3 = ref 0.
and dt_direct = ref 0.
and dt_msat = ref 0.
and dt_minisat = ref 0.
and res_sz3 = ref true
and res_msat = ref true
and res_minisat = ref true
and res_direct = ref true
and out = None (* Some (open_out "test.out") *)
and res = open_out_gen [Open_append] 777 "resultatsz3.csv"
and comp = ref 0
in begin
	for i = 1 to nb do
		let f = tire_form n in
		let f0 = C.st "w" f
		and a,_ = get_logic () in
		let module  Smsat = Solve.Solve(Smtmsat.SMTmsat(Dummy))
		in begin
			pf "========================= \n";
			(*
			PP.print_m f;
			*)
			flush_all ();

		(*
		On fait les résolutions avec les différents oracles
		*)

	 		t0 := U.gettimeofday () ;
			res_sz3 := Sz3.solve f0 a ;
			dt_sz3 := (U.gettimeofday () -. !t0);
			t_sz3 := !t_sz3 +. !dt_sz3;


			t0 := U.gettimeofday () ;
			res_msat := Smsat.solve f0 a ;
			dt_msat:= (U.gettimeofday () -. !t0);
			t_msat := !t_msat +. !dt_msat;


	 		t0 := U.gettimeofday () ;
			res_minisat := Sminisat.solve f0 a ;
			dt_minisat:= (U.gettimeofday () -. !t0);
			t_minisat := !t_minisat +. !dt_minisat;

	 		t0 := U.gettimeofday () ;
			res_direct := D.solve f0 a ;
			dt_direct := (U.gettimeofday () -. !t0);
			t_direct := !t_direct +. !dt_direct;

			res_direct := !res_minisat;
		(*
		On regarde si au moins un des solveurs a fait mieux que "direct"

		*)


			if !dt_sz3 < !dt_direct
				|| !dt_minisat < !dt_direct
				|| !dt_msat < !dt_direct
			then
				incr comp;

		(*
		On vérifie ensuite que les solveurs trouvent bien la même chiose
		que le mode "direct"
		*)
			if !res_sz3 != !res_direct then
			begin
				output_string res "FAIL \n";
				pf "\027[31m =====>   FAIL !!!!  <=====\027[0m\n";
				pf "\027[31m =====>      z3      <=====\027[0m\n";
				exit 1;
			end;


			if !res_msat != !res_direct then
			begin
				output_string res "FAIL \n";
				pf "\027[31m =====>   FAIL !!!!  <=====\027[0m\n";
				pf "\027[31m =====>     msat     <=====\027[0m\n";
				exit 1;
			end;


			if !res_minisat != !res_direct then
			begin
				output_string res "FAIL \n";
				pf "\027[31m =====>   FAIL !!!!  <=====\027[0m\n";
				pf "\027[31m =====>    minisat   <=====\027[0m\n";
				exit 1;
			end;

		end;
	done;
	let t_mol_f = 	(!t_sz3/. (float_of_int nb))
	and t_direct_f = (!t_direct /. (float_of_int nb))
	and t_msat_f = (!t_msat /. (float_of_int nb))
	and t_minisat_f = (!t_minisat /. (float_of_int nb))
	and _,logic = get_logic ()
	and tx = (float_of_int !comp) /. (float_of_int nb)
	and result =
			if !res_direct then "SAT"
					   else "UNSAT"
	in begin
		pf "Calculs effectués en : \n" ;
		pf "Pour Moloss (z3) : %f \n" t_mol_f;
		pf "Pour Moloss (msat) : %f \n" t_msat_f;
		pf "Pour Moloss (minisat) : %f \n" t_minisat_f;
  pf "Pour z3 : %f \n" t_direct_f;
		pf "taux : %f \n" tx;
		flush_all ();
		(*
		output_string res
			(*
			(spf "%s,%s, %d,%f,%f,%f,%f \n"
			*)
			(spf "%s,%s, %d,%f,%f,%f,%f \n"
				logic
				result
				n
				t_mol_f
				t_msat_f
				t_minisat_f
				t_z3_f);
			*)
	end;

end
