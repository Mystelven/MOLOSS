(*########################################################*)
(*               Essai d'un solveur basique               *) 
(*########################################################*)
(*
TODO : rassembler les morceaux de code dans un seul module/dossier : +
correcte
*)

(*--------------------------------------------------------*)
(*              Types & modules manipulés                 *)
(*--------------------------------------------------------*)

open Ast_fo
open Lexing
open Format


module PP = Pprinter
module U = Unix
module FOMap = Map.Make(FO)
module FOSet = Set.Make(FO)
module Smap = Map.Make(String)
module SSet = Set.Make(String)
module DS = struct
	type t= string*string
	let compare = compare
end
module DSSet = Set.Make(DS)



type ident = string



module BFOSet = Set.Make(BFO)

type ans = SAT | UNSAT

type config = 
	{mutable w : SSet.t; (* liste des mondes possibles *)
	 mutable env : FO.formula Smap.t; (* string -> formula *)
	 mutable s : BFOSet.t; (* ensmble S *)
	 mutable exists : SSet.t; (* ensemble \Theta_\exists *)
	 mutable forall : DSSet.t} (* ensemble \Theta_\forall *)

let spf = Format.sprintf
and fpf = Format.printf

type dicided = 
	| Sat
	| Todo of config*BFO.formula*(string list)
	(* nouvelle config, formule en plus, varaibles en plus *)


(*--------------------------------------------------------*)
(*              Fonction sur les config                   *)
(*--------------------------------------------------------*)

let rec init_config = function 
(*
Prend une liste de FO.formula et renvoie une config vide dont s et env
contiennent la liste de formule
*)
| [] -> 
	{w = SSet.singleton "w"; 
	 env = Smap.empty ; 
	 s = BFOSet.empty;
	 forall = DSSet.empty;
	 exists = SSet.empty}
| f :: q -> 
	let config = init_config q in
	let bf,new_env,_ = abs config.env f
	in begin
		config.env <- new_env;
		config.s <- BFOSet.add bf config.s;
		config;
	end
		
(*--------------------------------------------------------*)
(*                 Fonction de décision                   *)
(*--------------------------------------------------------*)

(*
possible de passer les règles exists & Forall en fonction annexe : 
code + lisible , TODO
*)

let decide modele config = 
	let rec make_rel modele config = 
	(* Construction des relations dans le modèle *)
	match modele with
	| [] -> []
	| (eps,b)::q when b -> 
	begin
		match Smap.find eps config.env with
		| FO.Relation (c,d) -> (c,d)::(make_rel q config)
		| _ -> make_rel q config
	end
	| _::q -> make_rel q config
	and  aux modele config rel = 
	(* ============== coeur de la fonction ===================*)
	match modele with
	| [] -> Sat 
	| (eps,b)::q when b = true -> 
	begin
		let f = Smap.find eps config.env in
		match f with
		| FO.Atom _ | FO.Relation _ -> 
			aux q config rel
		| FO.Exists (y,fy) ->
		(* =============== règle exists ======================  *)
		begin
			if (SSet.mem eps config.exists) then
				aux q config rel
			else
				let w = get_fw () in
				let fd = match fy with 
				| FO.Conj (FO.Relation(c,y),fy) ->
					FO.Conj (FO.Relation(c,w),FO.changefv w fy)
				| _ -> assert false	
				in
					let f_tot,new_env,new_var = 
						abs config.env (FO.Dij (FO.Not f,fd))
					in begin
						config.w <- SSet.add w config.w;
						config.s <- BFOSet.add f_tot config.s;
						config.env <- new_env;
						config.exists <- SSet.add eps config.exists;
						Todo (config,f_tot,new_var);
					end
		end
		| FO.Forall (y,fy) ->
		(* =============== règle forall ======================  *)
		begin
			match fy with
			| FO.Dij (FO.Not (FO.Relation (c,y)),fy) ->
			begin
				let aux_find (c1,d1) = 
					c = c1 && not (DSSet.mem (eps,d1) config.forall) 
				in
				try 
					let d = snd (List.find aux_find rel) in
					let fd = 
						FO.Dij (FO.Not(FO.Relation(c,d)),FO.changefv d fy)
					in 
					let f_tot,new_env,new_var= 
						abs config.env	 (FO.Dij (FO.Not f,fd)) 
					in begin
						config.s <- BFOSet.add f_tot config.s;
						config.env <-new_env;
						config.forall <- DSSet.add (eps,d) config.forall;
						Todo (config,f_tot,new_var);
					end
				with Not_found -> aux q config rel
			end
			|_ -> assert false
		end
		| _ -> assert false
	end			
	| _::q ->
		aux q config rel 
	in aux modele config (make_rel modele config) 



(*--------------------------------------------------------*)
(*       Fonctions de conversion FO <-> SMT-LIB           *)
(*--------------------------------------------------------*)


let rec bfo_to_smtlib = function
| BFO.Atom i -> i
| BFO.Not f -> spf "(not %s)" (bfo_to_smtlib f)
| BFO.Conj (f1,f2) ->
	spf "(and %s %s)" (bfo_to_smtlib f1) (bfo_to_smtlib f2)
| BFO.Dij (f1,f2) ->
	spf "(or %s %s)" (bfo_to_smtlib f1) (bfo_to_smtlib f2)

let dec_const oc v = 
begin
	output_string oc (spf "(declare-const %s Bool) \n" v);
	flush_all ();
end


let dec_assert oc bf = 
	let f_smt = bfo_to_smtlib bf 
	in begin
	output_string oc (spf "(assert %s) \n" f_smt);
		flush_all ();
	end


let config_to_request config oc = 
(* Permet de configurer le deébut d'une requête *)
	let header = 
"(set-logic QF_UF) \n
(set-option :produce-models true)
(set-option :produce-proofs true) 
; Fin du header : déclaration des variables :\n"
	and mid = 
";Fin de déclaration, début des assertions :\n"
	and bottom = 
"; Fin des assertions : pour conclure :\n"
	in
	let aux_var v _ = 
		dec_const oc v
	and aux_asser f = 
		dec_assert oc f
	in begin
	flush_all ();
	output_string oc header;
	Smap.iter aux_var config.env;
	output_string oc mid;
	BFOSet.iter aux_asser config.s;
	output_string oc bottom; 
	flush_all ();
	end

(*--------------------------------------------------------*)
(*              Fonctions pour le parsing                 *)
(*--------------------------------------------------------*)


let report (b,e) =
  let l = b.pos_lnum in
  let fc = b.pos_cnum - b.pos_bol + 1 in
  let lc = e.pos_cnum - b.pos_bol + 1 in
  fpf "File \"%s\", line %d, characters %d-%d:\n" "model" l fc lc
 


let get_model oc ic = 
begin
	flush_all ();
	output_string oc "(get-model) \n";
	flush_all ();
	let res = ref ""
	and cont = ref true 
	in begin
		while !cont do 
			let ligne = input_line ic 
			in begin
			res := spf "%s \n%s" !res ligne;
			if ligne = ")" then
				cont := false;
			end;
		done;
	let lb = Lexing.from_string !res in
	try 
		Z3_parser.answer Z3_lexer.next_token lb
	with

	| Z3_lexer.Lex_err s ->
	report (lexeme_start_p lb, lexeme_end_p lb);
	fpf "lexical error: %s.\n" s;
	flush_all ();
	exit 1
    | Z3_parser.Error ->
	report (lexeme_start_p lb, lexeme_end_p lb);
	fpf "syntax error.\n";
	flush_all ();
	exit 1
	end;
end

let get_ans oc ic = 
begin
	output_string oc "(check-sat) \n";
	flush_all ();
	let ans = input_line ic in
	if ans = "unsat" then
		UNSAT
	else
		SAT
end


(*--------------------------------------------------------*)
(*                Fonction de résolution                  *)
(*--------------------------------------------------------*)


let print_soluce config m = 
let aux (k,b) = 
	let f = Smap.find k config.env in
	match b with
	| true -> PP.print_fo f
	| false -> PP.print_fo (FO.Not f)
in begin
	fpf "liste des mondes : \n";
	SSet.iter (fun s -> fpf "%s \n" s) config.w;
	flush_all ();
	fpf "\nPropriétés à vérifier :\n ";	
	List.iter aux m;
	flush_all ();
end

let solve f = 
	let config = ref (init_config [f] )
	and ic,oc = U.open_process "./z3 -in"
	and cont = ref true 
	in begin
		config_to_request !config oc;
		while !cont do
			match get_ans oc ic with
			| UNSAT ->

			begin
				fpf "La formule est insatisfiable \n";
				flush_all ();
				cont := false; 
			end
			| SAT -> let m = get_model oc ic in
				match decide m !config with
				| Sat ->
				begin
					fpf "La formule est satisfiable \n";
					print_soluce !config m;
					flush_all ();
					cont := false; 
				end
				| Todo (new_config,new_bf,new_var) ->
				begin
					config := new_config;
					List.iter (fun v -> dec_const oc v) new_var;
					dec_assert oc new_bf;
				end;
		done;
		fpf "Terminé !!! \n";
		flush_all ();
	end
					
			


























