(* Termination for D<:> *)
(* this version includes a proof of totality *)

(*
 DSub (D<:) + Bot
 T ::= Top | Bot | x.Type | { Type: S..U } | (z: T) -> T^z
 t ::= x | { Type = T } | lambda x:T.t | t t
 *)

Require Export SfLib.

Require Export Arith.EqNat.
Require Export Arith.Le.
Require Import Coq.Program.Equality.
Require Import Omega.

(* ### Syntax ### *)

Definition id := nat.

(* term variables occurring in types *)
Inductive var : Type :=
| varF : id -> var (* free, in concrete environment *)
| varH : id -> var (* free, in abstract environment  *)
| varB : id -> var (* locally-bound variable *)
.

Inductive ty : Type :=
| TTop : ty
| TBot : ty
(* (z: T) -> T^z *)
| TAll : ty -> ty -> ty
(* x.Type *)
| TSel : var -> ty
(* { Type: S..U } *)
| TMem : ty(*S*) -> ty(*U*) -> ty
.

Inductive tm : Type :=
(* x -- free variable, matching concrete environment *)
| tvar : id -> tm
(* { Type = T } *)
| ttyp : ty -> tm
(* lambda x:T.t *)
| tabs : ty -> tm -> tm
(* t t *)
| tapp : tm -> tm -> tm
.

Inductive vl : Type :=
(* a closure for a lambda abstraction *)
| vabs : list vl (*H*) -> ty -> tm -> vl
(* a closure for a first-class type *)
| vty : list vl (*H*) -> ty -> vl
.

Definition tenv := list ty. (* Gamma environment: static *)
Definition venv := list vl. (* H environment: run-time *)


(* ### Representation of Bindings ### *)

(* An environment is a list of values, indexed by decrementing ids. *)

Fixpoint indexr {X : Type} (n : id) (l : list X) : option X :=
  match l with
    | [] => None
    | a :: l' =>
      if (beq_nat n (length l')) then Some a else indexr n l'
  end.

Inductive closed: nat(*B*) -> nat(*H*) -> nat(*F*) -> ty -> Prop :=
| cl_top: forall i j k,
    closed i j k TTop
| cl_bot: forall i j k,
    closed i j k TBot
| cl_all: forall i j k T1 T2,
    closed i j k T1 ->
    closed (S i) j k T2 ->
    closed i j k (TAll T1 T2)
| cl_sel: forall i j k x,
    k > x ->
    closed i j k (TSel (varF x))
| cl_selh: forall i j k x,
    j > x ->
    closed i j k (TSel (varH x))
| cl_selb: forall i j k x,
    i > x ->
    closed i j k (TSel (varB x))
| cl_mem: forall i j k T1 T2,
    closed i j k T1 ->
    closed i j k T2 ->
    closed i j k (TMem T1 T2)
.

(* open define a locally-nameless encoding wrt to TVarB type variables. *)
(* substitute var u for all occurrences of (varB k) *)
Fixpoint open_rec (k: nat) (u: var) (T: ty) { struct T }: ty :=
  match T with
    | TTop        => TTop
    | TBot        => TBot
    | TAll T1 T2  => TAll (open_rec k u T1) (open_rec (S k) u T2)
    | TSel (varF x) => TSel (varF x)
    | TSel (varH i) => TSel (varH i)
    | TSel (varB i) => if beq_nat k i then TSel u else TSel (varB i)
    | TMem T1 T2  => TMem (open_rec k u T1) (open_rec k u T2)
  end.

Definition open u T := open_rec 0 u T.

(* Locally-nameless encoding with respect to varH variables. *)
Fixpoint subst (U : var) (T : ty) {struct T} : ty :=
  match T with
    | TTop         => TTop
    | TBot         => TBot
    | TAll T1 T2   => TAll (subst U T1) (subst U T2)
    | TSel (varB i) => TSel (varB i)
    | TSel (varF i) => TSel (varF i)
    | TSel (varH i) => if beq_nat i 0 then TSel U else TSel (varH (i-1))
    | TMem T1 T2     => TMem (subst U T1) (subst U T2)
  end.

Fixpoint nosubst (T : ty) {struct T} : Prop :=
  match T with
    | TTop         => True
    | TBot         => True
    | TAll T1 T2   => nosubst T1 /\ nosubst T2
    | TSel (varB i) => True
    | TSel (varF i) => True
    | TSel (varH i) => i <> 0
    | TMem T1 T2    => nosubst T1 /\ nosubst T2
  end.

(* ### Subtyping ### *)
(*
Note: In contrast to the rules on paper, the subtyping
relation has two environments instead of just one.
(The same holds for the semantic types, val_type, below).
This split into an abstract and a concrete environment
was necessary in the D<: soundness development, but is
not required here. We just keep it for consistency with
our earlier Coq files.

The first env is for looking up varF variables.
The first env matches the concrete runtime environment, and is
extended during type assignment.
The second env is for looking up varH variables.
The second env matches the abstract runtime environment, and is
extended during subtyping.
*)
Inductive stp: tenv -> tenv -> ty -> ty -> Prop :=
| stp_top: forall G1 GH T1,
    closed 0 (length GH) (length G1) T1 ->
    stp G1 GH T1 TTop
| stp_bot: forall G1 GH T2,
    closed 0 (length GH) (length G1) T2 ->
    stp G1 GH TBot T2
| stp_mem: forall G1 GH S1 U1 S2 U2,
    stp G1 GH U1 U2 ->
    stp G1 GH S2 S1 ->
    stp G1 GH (TMem S1 U1) (TMem S2 U2)
| stp_sel1: forall G1 GH TX T2 x,
    indexr x G1 = Some TX ->
    closed 0 0 (length G1) TX ->
    stp G1 GH TX (TMem TBot T2) ->
    stp G1 GH (TSel (varF x)) T2
| stp_sel2: forall G1 GH TX T1 x,
    indexr x G1 = Some TX ->
    closed 0 0 (length G1) TX ->
    stp G1 GH TX (TMem T1 TTop) ->
    stp G1 GH T1 (TSel (varF x))
| stp_selx: forall G1 GH v x,
    indexr x G1 = Some v ->
    stp G1 GH (TSel (varF x)) (TSel (varF x))
| stp_sela1: forall G1 GH TX T2 x,
    indexr x GH = Some TX ->
    closed 0 x (length G1) TX ->
    stp G1 GH TX (TMem TBot T2) ->
    stp G1 GH (TSel (varH x)) T2
| stp_sela2: forall G1 GH TX T1 x,
    indexr x GH = Some TX ->
    closed 0 x (length G1) TX ->
    stp G1 GH TX (TMem T1 TTop) ->
    stp G1 GH T1 (TSel (varH x))
| stp_selax: forall G1 GH v x,
    indexr x GH = Some v  ->
    stp G1 GH (TSel (varH x)) (TSel (varH x))
| stp_all: forall G1 GH T1 T2 T3 T4 x,
    stp G1 GH T3 T1 ->
    x = length GH ->
    closed 1 (length GH) (length G1) T2 ->
    closed 1 (length GH) (length G1) T4 ->
    stp G1 (T3::GH) (open (varH x) T2) (open (varH x) T4) ->
    stp G1 GH (TAll T1 T2) (TAll T3 T4)
| stp_trans: forall G1 GH T1 T2 T3,
    stp G1 GH T1 T2 ->
    stp G1 GH T2 T3 ->
    stp G1 GH T1 T3
.

(* ### Type Assignment ### *)
Inductive has_type : tenv -> tm -> ty -> Prop :=
| t_var: forall x env T1,
           indexr x env = Some T1 ->
           stp env [] T1 T1 ->
           has_type env (tvar x) T1
| t_typ: forall env T1,
           closed 0 0 (length env) T1 ->
           has_type env (ttyp T1) (TMem T1 T1)
| t_app: forall env f x T1 T2,
           has_type env f (TAll T1 T2) ->
           has_type env x T1 ->
           closed 0 0 (length env) T2 ->
           has_type env (tapp f x) T2
| t_dapp:forall env f x T1 T2 T,
           has_type env f (TAll T1 T2) ->
           has_type env (tvar x) T1 ->
           T = open (varF x) T2 ->
           closed 0 0 (length env) T ->
           has_type env (tapp f (tvar x)) T
| t_abs: forall env y T1 T2,
           has_type (T1::env) y (open (varF (length env)) T2) ->
           closed 0 0 (length env) (TAll T1 T2) ->
           has_type env (tabs T1 y) (TAll T1 T2)
| t_sub: forall env e T1 T2,
           has_type env e T1 ->
           stp env [] T1 T2 ->
           has_type env e T2
.



(* ### Evaluation (Big-Step Semantics) ### *)

(*
None             means timeout
Some None        means stuck
Some (Some v))   means result v
Could use do-notation to clean up syntax.
*)

Fixpoint teval(n: nat)(env: venv)(t: tm){struct n}: option (option vl) :=
  match n with
    | 0 => None
    | S n =>
      match t with
        | tvar x       => Some (indexr x env)
        | ttyp T       => Some (Some (vty env T))
        | tabs T y     => Some (Some (vabs env T y))
        | tapp ef ex   =>
          match teval n env ex with
            | None => None
            | Some None => Some None
            | Some (Some vx) =>
              match teval n env ef with
                | None => None
                | Some None => Some None
                | Some (Some (vty _ _)) => Some None
                | Some (Some (vabs env2 _ ey)) =>
                  teval n (vx::env2) ey
              end
          end
      end
  end.


Definition tevaln env e v := exists nm, forall n, n > nm -> teval n env e = Some (Some v).


(* ### Semantic Interpretation of Types (Logical Relations) ### *)

Fixpoint tsize_flat(T: ty) :=
  match T with
    | TTop => 1
    | TBot => 1
    | TAll T1 T2 => S (tsize_flat T1 + tsize_flat T2)
    | TSel _ => 1
    | TMem T1 T2 => S (tsize_flat T1 + tsize_flat T2)
  end.

Lemma open_preserves_size: forall T x j,
  tsize_flat T = tsize_flat (open_rec j (varH x) T).
Proof.
  intros T. induction T; intros; simpl; eauto.
  - destruct v; simpl; destruct (beq_nat j i); eauto.
Qed.

(* Selector strings for lower/upper bounds *)
Inductive bound: Type :=
| ub : bound
| lb : bound
.

Definition sel := list bound.

(* Polarity of selector strings *)
Fixpoint pos s :=
  match s with
    | nil => true
    | ub :: i => pos i
    | lb :: i => if (pos i) then false else true
  end.


(* Semantic types are sets of values, indexed by a list of lb/ub selectors *)
Definition vset := vl -> sel -> Prop.



(* Set inclusion, taking polarity into account *)
Definition vtsub (a: vset) (b: vset) := forall vy iy, if pos iy
          then a vy iy -> b vy iy
          else b vy iy -> a vy iy.

(* Good bounds property *)
Definition good_bounds (jj: vset) := (forall vp ip, jj vp ip -> forall vy iy, if pos iy
          then jj vy (ip ++ (lb::iy)) -> jj vy (ip ++ (ub::iy))
          else jj vy (ip ++ (ub::iy)) -> jj vy (ip ++ (lb::iy))).


(* Definition of semantic types: [[ T ]] = { v | ... } *)

Require Coq.Program.Wf.

Program Fixpoint val_type (env:list vset) (GH:list vset) (v:vl) (T:ty) (i:sel) {measure (tsize_flat T)}: Prop :=
  match v,T,i with
    | vabs env1 T0 y, TAll T1 T2, nil =>
      closed 0 (length GH) (length env) T1 /\ closed 1 (length GH) (length env) T2 /\
      forall vx (jj:vset),
        jj vx nil ->
        vtsub jj (fun vy iy => val_type env GH vy T1 iy) ->
        good_bounds jj ->
        exists v, tevaln (vx::env1) y v /\ val_type env (jj::GH) v (open (varH (length GH)) T2) nil
    | vty env1 TX, TMem T1 T2, nil =>
      closed 0 (length GH) (length env) T1 /\ closed 0 (length GH) (length env) T2
       /\ vtsub (fun vy iy => val_type env GH vy T1 iy) (fun vy iy => val_type env GH vy T2 iy)
    | _, TMem T1 T2, ub :: i =>
      closed 0 (length GH) (length env) T1 /\ closed 0 (length GH) (length env) T2
      /\ val_type env GH v T2 i
    | _, TMem T1 T2, lb :: i =>
      closed 0 (length GH) (length env) T1 /\ closed 0 (length GH) (length env) T2
      /\ val_type env GH v T1 i
    | _, TSel (varF x), _ =>
      match indexr x env with
        | Some jj => jj v (ub :: i)
        | _ => False
      end
    | _, TSel (varH x), _ =>
      match indexr x GH with
        | Some jj => jj v (ub :: i)
        | _ => False
      end
    | _, TTop, _ =>
      pos i = true
    | _, TAll T1 T2, _ =>
      closed 0 (length GH) (length env) T1 /\ closed 1 (length GH) (length env) T2 /\
      pos i = true /\ i <> nil
    | _, TBot, _ =>
      pos i = false
    | _,_,_ =>
      False
  end.

Next Obligation. simpl. omega. Qed.
Next Obligation. simpl. unfold open. rewrite <-open_preserves_size. omega. Qed. (* TApp case: open *)
Next Obligation. simpl. omega. Qed.
Next Obligation. simpl. omega. Qed.
Next Obligation. simpl. omega. Qed.
Next Obligation. simpl. omega. Qed.


Ltac ev := repeat match goal with
                    | H: exists _, _ |- _ => destruct H
                    | H: _ /\  _ |- _ => destruct H
           end.

Ltac inv_mem := match goal with
                  | H: closed 0 (length ?GH) (length ?G) (TMem ?T1 ?T2) |-
                    closed 0 (length ?GH) (length ?G) ?T2 => inversion H; subst; eauto
                  | H: closed 0 (length ?GH) (length ?G) (TMem ?T1 ?T2) |-
                    closed 0 (length ?GH) (length ?G) ?T1 => inversion H; subst; eauto
                end.

Next Obligation. compute. repeat split; intros; ev; try solve by inversion. Qed.
Next Obligation. compute. repeat split; intros; ev; try solve by inversion. Qed.
Next Obligation. compute. repeat split; intros; ev; try solve by inversion. Qed.

(*
   The expansion of val_type, val_type_func is incomprehensible.
   We cannot (easily) unfold and reason about it. Therefore, we
   prove unfolding of val_type to its body as a lemma.
   (Note that the unfold_sub tactic relies on functional extensionality)
*)

Import Coq.Program.Wf.
Import WfExtensionality.

Lemma val_type_unfold: forall env GH v T i, val_type env GH v T i =
  match v,T,i with
    | vabs env1 T0 y, TAll T1 T2, nil =>
      closed 0 (length GH) (length env) T1 /\ closed 1 (length GH) (length env) T2 /\
      forall vx (jj:vset),
        jj vx nil ->
        vtsub jj (fun vy iy => val_type env GH vy T1 iy) ->
        good_bounds jj ->
        exists v, tevaln (vx::env1) y v /\ val_type env (jj::GH) v (open (varH (length GH)) T2) nil
    | vty env1 TX, TMem T1 T2, nil =>
      closed 0 (length GH) (length env) T1 /\ closed 0 (length GH) (length env) T2
       /\ vtsub (fun vy iy => val_type env GH vy T1 iy) (fun vy iy => val_type env GH vy T2 iy)
    | _, TMem T1 T2, ub :: i =>
      closed 0 (length GH) (length env) T1 /\ closed 0 (length GH) (length env) T2
      /\ val_type env GH v T2 i
    | _, TMem T1 T2, lb :: i =>
      closed 0 (length GH) (length env) T1 /\ closed 0 (length GH) (length env) T2
      /\ val_type env GH v T1 i
    | _, TSel (varF x), _ =>
      match indexr x env with
        | Some jj => jj v (ub :: i)
        | _ => False
      end
    | _, TSel (varH x), _ =>
      match indexr x GH with
        | Some jj => jj v (ub :: i)
        | _ => False
      end
    | _, TTop, _ =>
      pos i = true
    | _, TAll T1 T2, _ =>
      closed 0 (length GH) (length env) T1 /\ closed 1 (length GH) (length env) T2 /\
      pos i = true /\ i <> nil
    | _, TBot, _ =>
      pos i = false
    | _,_,_ =>
      False
  end.
Proof.
  intros. unfold val_type at 1. unfold val_type_func.
  unfold_sub val_type (val_type env GH v T i).
  simpl.
  (* unfold_sub and simpl above may take a long time, up to minutes *)
  destruct v; simpl; try reflexivity.
  destruct T.
  - destruct i; simpl; try reflexivity.
  - simpl; try reflexivity.
  - destruct i; destruct T1; simpl; eauto.
  - destruct v; simpl; try reflexivity.

  (* TSel case has another match *)
  destruct (indexr i0 env); simpl; try reflexivity;
  destruct v; simpl; try reflexivity.
  (* TSelH *)
  destruct (indexr i0 GH); simpl; try reflexivity.
  - destruct i; try destruct b; reflexivity.
  -  destruct T; simpl; try reflexivity;
     try destruct v; simpl; try reflexivity.
     destruct (indexr i0 env); simpl; try reflexivity;
       destruct v; simpl; try reflexivity.
     destruct (indexr i0 GH); simpl; try reflexivity.

     destruct i; try destruct b; reflexivity.
Qed.


(* this is just to accelerate Coq -- val_type in the goal is slooow *)
Inductive vtp: list vset -> list vset -> vl -> ty -> sel -> Prop :=
| vv: forall G H v T i, val_type G H v T i -> vtp G H v T i.


Lemma unvv: forall G H v T i,
  vtp G H v T i -> val_type G H v T i.
Proof.
  intros. inversion H0. subst. apply H2.
Qed.


(* make logical relation explicit *)
Definition R H G t v T := tevaln H t v /\ val_type G [] v T nil.


(* consistent environment *)
Definition R_env venv genv tenv :=
  length venv = length tenv /\
  length genv = length tenv /\
  forall x TX, indexr x tenv = Some TX ->
    (exists v : vl, R venv genv (tvar x) v TX) /\ (* not strictly needed *)
    (exists vx (jj:vset),
       indexr x venv = Some vx /\
       indexr x genv = Some jj /\
       jj vx nil /\
       vtsub jj (fun vy iy => vtp genv [] vy TX iy) /\
       good_bounds jj).


(* automation *)
Hint Unfold venv.
Hint Unfold tenv.

Hint Unfold open.
Hint Unfold indexr.
Hint Unfold length.

Hint Unfold R.
Hint Unfold R_env.

Hint Constructors ty.
Hint Constructors tm.
Hint Constructors vl.

Hint Constructors closed.
Hint Constructors has_type.
Hint Constructors stp.

Hint Constructors option.
Hint Constructors list.

Hint Resolve ex_intro.

(* ############################################################ *)
(* Examples *)
(* ############################################################ *)


Ltac crush :=
  try solve [eapply stp_selx; compute; eauto; crush];
  try solve [eapply stp_selax; compute; eauto; crush];
  try solve [econstructor; compute; eauto; crush];
  try solve [eapply t_sub; crush].

(* define polymorphic identity function *)

Definition polyId := TAll (TMem TBot TTop) (TAll (TSel (varB 0)) (TSel (varB 1))).

Example ex1: has_type [] (tabs (TMem TBot TTop) (tabs (TSel (varF 0)) (tvar 1))) polyId.
Proof.
  crush.
Qed.

(* instantiate it to TTop *)
(*
Example ex2: has_type [polyId] (tapp (tvar 0) (ttyp TTop)) (TAll TTop TTop).
Proof.
  crush.
Qed.
*)

(* ############################################################ *)
(* Proofs *)
(* ############################################################ *)



(* ## Extension, Regularity ## *)

Lemma wf_length : forall vs gs ts,
                    R_env vs gs ts ->
                    (length vs = length ts).
Proof.
  intros. induction H. auto.
Qed.

Lemma wf_length2 : forall vs gs ts,
                    R_env vs gs ts ->
                    (length gs = length ts).
Proof.
  intros. destruct H. destruct H0. auto.
Qed.


Hint Immediate wf_length.

Lemma indexr_max : forall X vs n (T: X),
                       indexr n vs = Some T ->
                       n < length vs.
Proof.
  intros X vs. induction vs.
  - (* Case "nil". *)
    intros. inversion H.
  -  (* Case "cons". *)
    intros. inversion H.
    case_eq (beq_nat n (length vs)); intros E2.
    + (* SSCase "hit". *)
      eapply beq_nat_true in E2. subst n. compute. eauto.
    + (* SSCase "miss". *)
      rewrite E2 in H1.
      assert (n < length vs). eapply IHvs. apply H1.
      compute. eauto.
Qed.

Lemma le_xx : forall a b,
                       a <= b ->
                       exists E, le_lt_dec a b = left E.
Proof. intros.
  case_eq (le_lt_dec a b). intros. eauto.
  intros. omega.
Qed.
Lemma le_yy : forall a b,
                       a > b ->
                       exists E, le_lt_dec a b = right E.
Proof. intros.
  case_eq (le_lt_dec a b). intros. omega.
  intros. eauto.
Qed.

Lemma indexr_extend : forall X vs n x (T: X),
                       indexr n vs = Some T ->
                       indexr n (x::vs) = Some T.

Proof.
  intros.
  assert (n < length vs). eapply indexr_max. eauto.
  assert (beq_nat n (length vs) = false) as E. eapply beq_nat_false_iff. omega.
  unfold indexr. unfold indexr in H. rewrite H. rewrite E. reflexivity.
Qed.

(* splicing -- for stp_extend. *)

Fixpoint splice n (T : ty) {struct T} : ty :=
  match T with
    | TTop         => TTop
    | TBot         => TBot
    | TAll T1 T2   => TAll (splice n T1) (splice n T2)
    | TSel (varF i) => TSel (varF i)
    | TSel (varB i) => TSel (varB i)
    | TSel (varH i) => if le_lt_dec n i then TSel (varH (i+1)) else TSel (varH i)
    | TMem T1 T2   => TMem (splice n T1) (splice n T2)
  end.

Definition spliceat n (V: (venv*ty)) :=
  match V with
    | (G,T) => (G,splice n T)
  end.

Lemma splice_open_permute: forall {X} (G0:list X) T2 n j,
(open_rec j (varH (n + S (length G0))) (splice (length G0) T2)) =
(splice (length G0) (open_rec j (varH (n + length G0)) T2)).
Proof.
  intros X G T. induction T; intros; simpl; eauto;
  try rewrite IHT1; try rewrite IHT2; try rewrite IHT; eauto;
  destruct v; eauto.

  case_eq (le_lt_dec (length G) i); intros E LE; simpl; eauto.
  rewrite LE. eauto.
  rewrite LE. eauto.
  case_eq (beq_nat j i); intros E; simpl; eauto.
  case_eq (le_lt_dec (length G) (n + length G)); intros EL LE.
  rewrite E.
  assert (n + S (length G) = n + length G + 1). omega.
  rewrite H. eauto.
  omega.
  rewrite E. eauto.
Qed.

Lemma indexr_splice_hi: forall G0 G2 x0 v1 T,
    indexr x0 (G2 ++ G0) = Some T ->
    length G0 <= x0 ->
    indexr (x0 + 1) (map (splice (length G0)) G2 ++ v1 :: G0) = Some (splice (length G0) T).
Proof.
  intros G0 G2. induction G2; intros.
  - eapply indexr_max in H. simpl in H. omega.
  - simpl in H.
    case_eq (beq_nat x0 (length (G2 ++ G0))); intros E.
    + rewrite E in H. inversion H. subst. simpl.
      rewrite app_length in E.
      rewrite app_length. rewrite map_length. simpl.
      assert (beq_nat (x0 + 1) (length G2 + S (length G0)) = true). {
        eapply beq_nat_true_iff. eapply beq_nat_true_iff in E. omega.
      }
      rewrite H1. eauto.
    + rewrite E in H.  eapply IHG2 in H. eapply indexr_extend. eapply H. eauto.
Qed.

Lemma indexr_spliceat_hi: forall G0 G2 x0 v1 G T,
    indexr x0 (G2 ++ G0) = Some (G, T) ->
    length G0 <= x0 ->
    indexr (x0 + 1) (map (spliceat (length G0)) G2 ++ v1 :: G0) =
    Some (G, splice (length G0) T).
Proof.
  intros G0 G2. induction G2; intros.
  - eapply indexr_max in H. simpl in H. omega.
  - simpl in H. destruct a.
    case_eq (beq_nat x0 (length (G2 ++ G0))); intros E.
    + rewrite E in H. inversion H. subst. simpl.
      rewrite app_length in E.
      rewrite app_length. rewrite map_length. simpl.
      assert (beq_nat (x0 + 1) (length G2 + S (length G0)) = true). {
        eapply beq_nat_true_iff. eapply beq_nat_true_iff in E. omega.
      }
      rewrite H1. eauto.
    + rewrite E in H.  eapply IHG2 in H. eapply indexr_extend. eapply H. eauto.
Qed.

Lemma plus_lt_contra: forall a b,
  a + b < b -> False.
Proof.
  intros a b H. induction a.
  - simpl in H. apply lt_irrefl in H. assumption.
  - simpl in H. apply IHa. omega.
Qed.

Lemma indexr_splice_lo0: forall {X} G0 G2 x0 (T:X),
    indexr x0 (G2 ++ G0) = Some T ->
    x0 < length G0 ->
    indexr x0 G0 = Some T.
Proof.
  intros X G0 G2. induction G2; intros.
  - simpl in H. apply H.
  - simpl in H.
    case_eq (beq_nat x0 (length (G2 ++ G0))); intros E.
    + eapply beq_nat_true_iff in E. subst.
      rewrite app_length in H0. apply plus_lt_contra in H0. inversion H0.
    + rewrite E in H. apply IHG2. apply H. apply H0.
Qed.

Lemma indexr_extend_mult: forall {X} G0 G2 x0 (T:X),
    indexr x0 G0 = Some T ->
    indexr x0 (G2++G0) = Some T.
Proof.
  intros X G0 G2. induction G2; intros.
  - simpl. assumption.
  - simpl.
    case_eq (beq_nat x0 (length (G2 ++ G0))); intros E.
    + eapply beq_nat_true_iff in E.
      apply indexr_max in H. subst.
      rewrite app_length in H. apply plus_lt_contra in H. inversion H.
    + apply IHG2. assumption.
Qed.

Lemma indexr_splice_lo: forall G0 G2 x0 v1 T f,
    indexr x0 (G2 ++ G0) = Some T ->
    x0 < length G0 ->
    indexr x0 (map (splice f) G2 ++ v1 :: G0) = Some T.
Proof.
  intros.
  assert (indexr x0 G0 = Some T). eapply indexr_splice_lo0; eauto.
  eapply indexr_extend_mult. eapply indexr_extend. eauto.
Qed.

Lemma indexr_spliceat_lo: forall G0 G2 x0 v1 G T f,
    indexr x0 (G2 ++ G0) = Some (G, T) ->
    x0 < length G0 ->
    indexr x0 (map (spliceat f) G2 ++ v1 :: G0) = Some (G, T).
Proof.
  intros.
  assert (indexr x0 G0 = Some (G, T)). eapply indexr_splice_lo0; eauto.
  eapply indexr_extend_mult. eapply indexr_extend. eauto.
Qed.

Lemma closed_splice: forall i j k T n,
  closed i j k T ->
  closed i (S j) k (splice n T).
Proof.
  intros. induction H; simpl; eauto.
  case_eq (le_lt_dec n x); intros E LE.
  apply cl_selh. omega.
  apply cl_selh. omega.
Qed.

Lemma map_splice_length_inc: forall G0 G2 v1,
   (length (map (splice (length G0)) G2 ++ v1 :: G0)) = (S (length (G2 ++ G0))).
Proof.
  intros. rewrite app_length. rewrite map_length. induction G2.
  - simpl. reflexivity.
  - simpl. eauto.
Qed.

Lemma map_spliceat_length_inc: forall G0 G2 v1,
   (length (map (spliceat (length G0)) G2 ++ v1 :: G0)) = (S (length (G2 ++ G0))).
Proof.
  intros. rewrite app_length. rewrite map_length. induction G2.
  - simpl. reflexivity.
  - simpl. eauto.
Qed.

Lemma closed_inc_mult: forall i j k T,
  closed i j k T ->
  forall i' j' k',
  i' >= i -> j' >= j -> k' >= k ->
  closed i' j' k' T.
Proof.
  intros i j k T H. induction H; intros; eauto; try solve [constructor; omega].
  - apply cl_all. apply IHclosed1; omega. apply IHclosed2; omega.
Qed.

Lemma closed_inc: forall i j k T,
  closed i j k T ->
  closed i (S j) k T.
Proof.
  intros. apply (closed_inc_mult i j k T H i (S j) k); omega.
Qed.

Lemma closed_splice_idem: forall i j k T n,
                            closed i j k T ->
                            n >= j ->
                            splice n T = T.
Proof.
  intros. induction H; eauto.
  - (* TAll *) simpl.
    rewrite IHclosed1. rewrite IHclosed2.
    reflexivity.
    assumption. assumption.
  - (* TVarH *) simpl.
    case_eq (le_lt_dec n x); intros E LE. omega. reflexivity.
  - (* TMem *) simpl.
    rewrite IHclosed1. rewrite IHclosed2.
    reflexivity.
    assumption. assumption.
Qed.


Lemma stp_closed : forall G GH T1 T2,
                     stp G GH T1 T2 ->
                     closed 0 (length GH) (length G) T1 /\ closed 0 (length GH) (length G) T2.
Proof.
  intros. induction H;
    try solve [repeat ev; split; try inv_mem; eauto using indexr_max].
Qed.

Lemma stp_closed2 : forall G1 GH T1 T2,
                       stp G1 GH T1 T2 ->
                       closed 0 (length GH) (length G1) T2.
Proof.
  intros. apply (proj2 (stp_closed G1 GH T1 T2 H)).
Qed.

Lemma stp_closed1 : forall G1 GH T1 T2,
                       stp G1 GH T1 T2 ->
                       closed 0 (length GH) (length G1) T1.
Proof.
  intros. apply (proj1 (stp_closed G1 GH T1 T2 H)).
Qed.


Lemma closed_upgrade: forall i j k i' T,
 closed i j k T ->
 i' >= i ->
 closed i' j k T.
Proof.
 intros. apply (closed_inc_mult i j k T H i' j k); omega.
Qed.

Lemma closed_upgrade_free: forall i j k j' T,
 closed i j k T ->
 j' >= j ->
 closed i j' k T.
Proof.
 intros. apply (closed_inc_mult i j k T H i j' k); omega.
Qed.

Lemma closed_upgrade_freef: forall i j k k' T,
 closed i j k T ->
 k' >= k ->
 closed i j k' T.
Proof.
 intros. apply (closed_inc_mult i j k T H i j k'); omega.
Qed.

Lemma closed_open: forall i j k V T, closed (i+1) j k T -> closed i j k (TSel V) ->
  closed i j k (open_rec i V T).
Proof.
  intros. generalize dependent i.
  induction T; intros; inversion H;
  try econstructor;
  try eapply IHT1; eauto; try eapply IHT2; eauto; try eapply IHT; eauto.
  eapply closed_upgrade. eauto. eauto.
  - (* Case "TVarB". *)
    simpl.
    case_eq (beq_nat i x); intros E. eauto.
    econstructor. eapply beq_nat_false_iff in E. omega.
Qed.

Lemma indexr_has: forall X (G: list X) x,
  length G > x ->
  exists v, indexr x G = Some v.
Proof.
  intros. remember (length G) as n.
  generalize dependent x.
  generalize dependent G.
  induction n; intros; try omega.
  destruct G; simpl.
  - simpl in Heqn. inversion Heqn.
  - simpl in Heqn. inversion Heqn. subst.
    case_eq (beq_nat x (length G)); intros E.
    + eexists. reflexivity.
    + apply beq_nat_false in E. apply IHn; eauto.
      omega.
Qed.

Lemma stp_refl_aux: forall n T G GH,
  closed 0 (length GH) (length G) T ->
  tsize_flat T < n ->
  stp G GH T T.
Proof.
  intros n. induction n; intros; try omega.
  inversion H; subst; eauto;
  try solve [omega];
  try solve [simpl in H0; constructor; apply IHn; eauto; try omega];
  try solve [apply indexr_has in H1; destruct H1; eauto].
  - simpl in H0.
    eapply stp_all.
    eapply IHn; eauto; try omega.
    reflexivity.
    assumption.
    assumption.
    apply IHn; eauto.
    simpl. apply closed_open; auto using closed_inc.
    unfold open. rewrite <- open_preserves_size. omega.
Qed.

Lemma stp_refl: forall T G GH,
  closed 0 (length GH) (length G) T ->
  stp G GH T T.
Proof.
  intros. apply stp_refl_aux with (n:=S (tsize_flat T)); eauto.
Qed.


Lemma concat_same_length: forall {X} (GU: list X) (GL: list X) (GH1: list X) (GH0: list X),
  GU ++ GL = GH1 ++ GH0 ->
  length GU = length GH1 ->
  GU=GH1 /\ GL=GH0.
Proof.
  intros. generalize dependent GH1. induction GU; intros.
  - simpl in H0. induction GH1. rewrite app_nil_l in H. rewrite app_nil_l in H.
    split. reflexivity. apply H.
    simpl in H0. omega.
  - simpl in H0. induction GH1. simpl in H0. omega.
    simpl in H0. inversion H0. simpl in H. inversion H. specialize (IHGU GH1 H4 H2).
    destruct IHGU. subst. split; reflexivity.
Qed.

Lemma concat_same_length': forall {X} (GU: list X) (GL: list X) (GH1: list X) (GH0: list X),
  GU ++ GL = GH1 ++ GH0 ->
  length GL = length GH0 ->
  GU=GH1 /\ GL=GH0.
Proof.
  intros.
  assert (length (GU ++ GL) = length (GH1 ++ GH0)) as A. {
    rewrite H. reflexivity.
  }
  rewrite app_length in A. rewrite app_length in A.
  rewrite H0 in A. apply Nat.add_cancel_r in A.
  apply concat_same_length; assumption.
Qed.


Lemma indexr_safe_ex: forall H1 GH G1 TF i,
             R_env H1 GH G1 ->
             indexr i G1 = Some TF ->
             exists v, indexr i H1 = Some v /\ val_type GH [] v TF nil.
Proof.
  intros. destruct H. destruct H2. destruct (H3 i TF H0) as [[v [E V]] G].
  exists v. split; eauto. destruct E as [n E].
  assert (S n > n) as N. omega. specialize (E (S n) N).
  simpl in E. inversion E. eauto.
Qed.





(* ### Substitution for relating static and dynamic semantics ### *)
Lemma indexr_hit2 {X}: forall x (B:X) A G,
  length G = x ->
  B = A ->
  indexr x (B::G) = Some A.
Proof.
  intros.
  unfold indexr.
  assert (beq_nat x (length G) = true). eapply beq_nat_true_iff. eauto.
  rewrite H1. subst. reflexivity.
Qed.

Lemma indexr_miss {X}: forall x (B:X) A G,
  indexr x (B::G) = A ->
  x <> (length G)  ->
  indexr x G = A.
Proof.
  intros.
  unfold indexr in H.
  assert (beq_nat x (length G) = false). eapply beq_nat_false_iff. eauto.
  rewrite H1 in H. eauto.
Qed.

Lemma indexr_hit {X}: forall x (B:X) A G,
  indexr x (B::G) = Some A ->
  x = length G ->
  B = A.
Proof.
  intros.
  unfold indexr in H.
  assert (beq_nat x (length G) = true). eapply beq_nat_true_iff. eauto.
  rewrite H1 in H. inversion H. eauto.
Qed.

Lemma indexr_hit0: forall GH (GX0:venv) (TX0:ty),
      indexr 0 (GH ++ [(GX0, TX0)]) =
      Some (GX0, TX0).
Proof.
  intros GH. induction GH.
  - intros. simpl. eauto.
  - intros. simpl. destruct a. simpl. rewrite app_length. simpl.
    assert (length GH + 1 = S (length GH)). omega. rewrite H.
    eauto.
Qed.

Hint Resolve beq_nat_true_iff.
Hint Resolve beq_nat_false_iff.

Lemma closed_no_open: forall T x i j k,
  closed i j k T ->
  T = open_rec i x T.
Proof.
  intros. induction H; intros; eauto;
  try solve [compute; compute in IHclosed; rewrite <-IHclosed; auto];
  try solve [compute; compute in IHclosed1; compute in IHclosed2;
             rewrite <-IHclosed1; rewrite <-IHclosed2; auto].

  (* Case "TVarB". *)
    unfold open_rec. assert (i <> x0). omega.
    apply beq_nat_false_iff in H0.
    rewrite H0. auto.
Qed.

Lemma open_subst_commute: forall T2 V j k x i,
closed i j k (TSel V) ->
(open_rec i (varH x) (subst V T2)) =
(subst V (open_rec i (varH (x+1)) T2)).
Proof.
  intros T2 TX j k. induction T2; intros; eauto; try destruct v; eauto.
  - simpl. rewrite IHT2_1; eauto. rewrite IHT2_2; eauto.
    eapply closed_upgrade. eauto. eauto.
  - simpl.
    case_eq (beq_nat i 0); intros E.
    apply beq_nat_true in E. subst.
    case_eq (beq_nat i0 0); intros E0.
    apply beq_nat_true in E0. subst.
    destruct TX; eauto.
    simpl. destruct i; eauto.
    inversion H; subst. omega.
    simpl. reflexivity.
    case_eq (beq_nat i0 0); intros E0.
    apply beq_nat_true in E0. subst.
    simpl. destruct TX; eauto.
    case_eq (beq_nat i i0); intros E1.
    apply beq_nat_true in E1. subst.
    inversion H; subst. omega.
    reflexivity.
    simpl. reflexivity.
  - simpl.
    case_eq (beq_nat i i0); intros E.
    apply beq_nat_true in E; subst.
    simpl.
    assert (x+1 <> 0) as A by omega.
    eapply beq_nat_false_iff in A.
    rewrite A.
    assert (x = x + 1 - 1) as B. unfold id. omega.
    rewrite <- B. reflexivity.
    simpl. reflexivity.
  - simpl. rewrite IHT2_1. rewrite IHT2_2. eauto. eauto. eauto.
Qed.

Lemma closed_no_subst: forall T i k TX,
   closed i 0 k T ->
   subst TX T = T.
Proof.
  intros T. induction T; intros; inversion H; simpl; eauto;
  try solve [rewrite (IHT i k TX); eauto; try omega];
  try solve [rewrite (IHT1 i k TX); eauto; rewrite (IHT2 (S i) k TX); eauto; try omega];
  try solve [rewrite (IHT1 i k TX); eauto; rewrite (IHT2 i k TX); eauto; try omega];
  try omega.
Qed.

Lemma closed_subst: forall i j k V T, closed i (j+1) k T -> closed 0 j k (TSel V) -> closed i j k (subst V T).
Proof.
  intros. generalize dependent i.
  induction T; intros; inversion H;
  try econstructor;
  try eapply IHT1; eauto; try eapply IHT2; eauto; try eapply IHT; eauto.

  - (* Case "TVarH". *)
    simpl.
    case_eq (beq_nat x 0); intros E.
    eapply closed_upgrade. eapply closed_upgrade_free.
    eauto. omega. eauto. omega.
    econstructor. assert (x > 0). eapply beq_nat_false_iff in E. omega. omega.
Qed.

Lemma closed_nosubst: forall i j k V T, closed i (j+1) k T -> nosubst T -> closed i j k (subst V T).
Proof.
  intros. generalize dependent i.
  induction T; intros; inversion H;
  try econstructor;
  try eapply IHT1; eauto; try eapply IHT2; eauto; try eapply IHT; eauto; subst;
  try inversion H0; eauto.

  - (* Case "TVarH". *)
    simpl. simpl in H0. unfold id in H0.
    assert (beq_nat x 0 = false) as E. apply beq_nat_false_iff. assumption.
    rewrite E.
    eapply cl_selh. omega.
Qed.

Lemma subst_open_commute_m: forall i j k k' j' V T2, closed (i+1) (j+1) k T2 -> closed 0 j' k' (TSel V) ->
    subst V (open_rec i (varH (j+1)) T2) = open_rec i (varH j) (subst V T2).
Proof.
  intros.
  generalize dependent i. generalize dependent j.
  induction T2; intros; inversion H; simpl; eauto; subst;
  try rewrite IHT2_1;
  try rewrite IHT2_2;
  try rewrite IHT2; eauto.
  - (* Case "TVarH". *)
    simpl. case_eq (beq_nat x 0); intros E.
    eapply closed_no_open. eapply closed_upgrade. eauto. omega.
    eauto.
  - (* Case "TVarB". *)
    simpl. case_eq (beq_nat i x); intros E.
    simpl. case_eq (beq_nat (j+1) 0); intros E2.
    eapply beq_nat_true_iff in E2. omega.
    subst. assert (j+1-1 = j) as A. omega. rewrite A. eauto.
    eauto.
Qed.

Lemma subst_open_commute: forall i j k k' V T2, closed (i+1) (j+1) k T2 -> closed 0 0 k' (TSel V) ->
    subst V (open_rec i (varH (j+1)) T2) = open_rec i (varH j) (subst V T2).
Proof.
  intros. eapply subst_open_commute_m; eauto.
Qed.

Lemma subst_open_zero: forall i i' k TX T2, closed i' 0 k T2 ->
    subst TX (open_rec i (varH 0) T2) = open_rec i TX T2.
Proof.
  intros. generalize dependent i'. generalize dependent i.
  induction T2; intros; inversion H; simpl; eauto;
  try solve [rewrite (IHT2_1 _ i'); eauto;
             rewrite (IHT2_2 _ (S i')); eauto;
             rewrite (IHT2_2 _ (S i')); eauto];
  try solve [rewrite (IHT2_1 _ i'); eauto;
             rewrite (IHT2_2 _ i'); eauto].
  subst.
  case_eq (beq_nat x 0); intros E. omega. omega.
  case_eq (beq_nat i x); intros E. eauto. eauto.
Qed.

Lemma Forall2_length: forall A B f (G1:list A) (G2:list B),
                        Forall2 f G1 G2 -> length G1 = length G2.
Proof.
  intros. induction H.
  eauto.
  simpl. eauto.
Qed.

Lemma nosubst_intro: forall i k T, closed i 0 k T -> nosubst T.
Proof.
  intros. generalize dependent i.
  induction T; intros; inversion H; simpl; eauto.
  omega.
Qed.

Lemma nosubst_open: forall i V T2, nosubst (TSel V) -> nosubst T2 -> nosubst (open_rec i V T2).
Proof.
  intros. generalize dependent i. induction T2; intros;
  try inversion H0; simpl; eauto; destruct v; eauto.
  case_eq (beq_nat i i0); intros E. eauto. eauto.
Qed.






(* ### Value Typing / Logical Relation for Values ### *)

(* NOTE: we need more generic internal lemmas, due to contravariance *)

(* used in valtp_widen *)
Lemma valtp_closed: forall vf GH H1 T1 i,
  val_type H1 GH vf T1 i ->
  closed 0 (length GH) (length H1) T1.
Proof.
  intros. destruct T1; destruct vf;
  rewrite val_type_unfold in H; try eauto; try contradiction.
  - (* fun *) destruct i; ev; econstructor; assumption.
  - ev; econstructor; assumption.
  - (* sel *) destruct v.
              remember (indexr i0 H1) as L; try destruct L as [?|]; try contradiction.
              constructor. eapply indexr_max. eauto.
              remember (indexr i0 GH) as L; try destruct L as [?|]; try contradiction.
              constructor. eapply indexr_max. eauto.
              inversion H.
  - (* sel *) destruct v.
              remember (indexr i0 H1) as L; try destruct L as [?|]; try contradiction.
              constructor. eapply indexr_max. eauto.
              remember (indexr i0 GH) as L; try destruct L as [?|]; try contradiction.
              constructor. eapply indexr_max. eauto.
              inversion H.
  - destruct i; try solve by inversion. destruct b.
    ev. constructor; assumption.
    ev. constructor; assumption.
  - destruct i; try solve by inversion.
    ev. constructor; assumption.
    destruct b.
    ev. constructor; try assumption.
    ev. constructor; try assumption.
Qed.


Lemma valtp_extend_aux: forall n T1 i vx vf H1 G1,
  tsize_flat T1 < n ->
  closed 0 (length G1) (length H1) T1 ->
  (vtp H1 G1 vf T1 i <-> vtp (vx :: H1) G1 vf T1 i).
Proof.
  induction n; intros ? ? ? ? ? ? S C. inversion S.
  destruct T1; split; intros V; apply unvv in V; rewrite val_type_unfold in V.
  - apply vv. rewrite val_type_unfold. assumption.
  - apply vv. rewrite val_type_unfold. assumption.
  - apply vv. rewrite val_type_unfold. assumption.
  - apply vv. rewrite val_type_unfold. assumption.
  - destruct vf. destruct i.
    + ev. apply vv. rewrite val_type_unfold. split.
    simpl. eapply closed_upgrade_freef. apply H. omega. split. simpl.
    eapply closed_upgrade_freef. apply H0. omega. intros.
    specialize (H2 _ _ H3).
    assert ((forall (vy : vl) (iy : sel),
      if pos iy
      then jj vy iy -> val_type H1 G1 vy T1_1 iy
      else val_type H1 G1 vy T1_1 iy -> jj vy iy)).
    { intros. destruct (pos iy) eqn : A. intros. specialize (H4 vy iy). rewrite A in H4.
      specialize (H4 H6). apply unvv. apply vv in H4. simpl in *. eapply IHn; try omega; try eassumption.
      intros. specialize (H4 vy iy). rewrite A in H4. apply H4. apply unvv. simpl in *.
      apply vv in H6. apply IHn; try omega; try eassumption. }
    specialize (H2 H6 H5). ev. exists x. split; try assumption.
    apply unvv. apply vv in H7. apply IHn; try eassumption. unfold open. erewrite <- open_preserves_size.
    simpl in *. omega. eapply closed_open. simpl. eapply closed_upgrade_free. eassumption. omega.
    constructor. simpl. omega.
    + apply vv. rewrite val_type_unfold. ev. repeat split; try assumption; try (eapply closed_upgrade_freef; [eassumption | simpl; auto]).
    + apply vv. rewrite val_type_unfold. ev. repeat split; try assumption; try (eapply closed_upgrade_freef; [eassumption | simpl; auto]).


- destruct vf. destruct i.
    + ev. apply vv. rewrite val_type_unfold. inversion C. subst.
    split; try assumption. split; try assumption. intros.
    specialize (H2 _ _ H3).
    assert ((forall (vy : vl) (iy : sel),
      if pos iy
      then jj vy iy -> val_type (vx :: H1) G1 vy T1_1 iy
      else val_type (vx :: H1) G1 vy T1_1 iy -> jj vy iy)).
    { intros. destruct (pos iy) eqn : A. intros. specialize (H4 vy iy). rewrite A in H4. specialize (H4 H6).
      apply unvv. apply vv in H4. simpl in *. apply IHn; try eassumption; try omega.
      specialize (H4 vy iy). rewrite A in H4. intros. apply H4. apply unvv. apply vv in H6.
      simpl in *. eapply IHn; try eassumption; try omega. }
    specialize (H2 H6 H5). ev. exists x. split; try assumption. apply unvv. apply vv in H7. eapply IHn; try eassumption.
    unfold open. erewrite <- open_preserves_size. simpl in *. omega. simpl. eapply closed_open.
    simpl. eapply closed_upgrade_free. eassumption. omega. constructor. omega.
    + apply vv. rewrite val_type_unfold. ev. inversion C. repeat split; assumption.
    + apply vv. rewrite val_type_unfold. ev. inversion C. repeat split; assumption.


  - apply vv. rewrite val_type_unfold. destruct vf.
    + destruct v.
    destruct (indexr i0 H1) eqn : A.
    assert (indexr i0 (vx :: H1) = Some v). apply indexr_extend. assumption. rewrite H. assumption.
    inversion V. assumption. inversion V.
    + destruct v.
    destruct (indexr i0 H1) eqn : A.
    assert (indexr i0 (vx :: H1) = Some v). apply indexr_extend. assumption. rewrite H. assumption.
    inversion V. assumption. inversion V.

  - apply vv. rewrite val_type_unfold. destruct vf.
    + destruct v. inversion C. subst.
    eapply indexr_has in H4. ev. assert (indexr i0 (vx:: H1) = Some x). apply indexr_extend.
    assumption. rewrite H0 in V. rewrite H. assumption. assumption. inversion V.
    + destruct v. inversion C. subst.
    eapply indexr_has in H4. ev. assert (indexr i0 (vx:: H1) = Some x). apply indexr_extend.
    assumption. rewrite H0 in V. rewrite H. assumption. assumption. inversion V.

  - inversion C. subst. apply vv. rewrite val_type_unfold. destruct vf. destruct i. inversion V.
    destruct b; ev. split. simpl. eapply closed_upgrade_freef. eassumption. omega.
    split. simpl. eapply closed_upgrade_freef. eassumption. omega.
    apply unvv. eapply IHn with (H1 := H1). simpl in *. omega. apply H6. apply vv. assumption.
    ev. split. simpl. eapply closed_upgrade_freef. eassumption. omega.
    split. simpl. eapply closed_upgrade_freef. eassumption. omega.
    apply unvv. eapply IHn with (H1 := H1). simpl in *. omega. assumption. apply vv. assumption.
    destruct i. simpl. ev. split. eapply closed_upgrade_freef; try eassumption; try omega.
    split. eapply closed_upgrade_freef; try eassumption; try omega.

    unfold vtsub. intros. destruct (pos iy) eqn : A. specialize (H2 vy iy). rewrite A in H2. intros.
    assert (val_type H1 G1 vy T1_1 iy). apply unvv. apply vv in H3. simpl in *. eapply IHn; try eassumption; try omega.
    specialize (H2 H4). apply unvv. apply vv in H2. simpl in *. eapply IHn with (H1 := H1); try eassumption; try omega.
            specialize (H2 vy iy). rewrite A in H2. intros. assert (val_type H1 G1 vy T1_2 iy).
    apply unvv. apply vv in H3. simpl in *. eapply IHn; try eassumption; try omega.
    specialize (H2 H4). simpl in *. apply unvv. apply vv in H2. eapply IHn with (H1 := H1); try eassumption; try omega.

    destruct b; ev. split. simpl. eapply closed_upgrade_freef. eassumption. omega.
    split. simpl. eapply closed_upgrade_freef. eassumption. omega.
    simpl in *. apply unvv. apply vv in H2. eapply IHn with (H1 := H1); try eassumption; try omega.
    simpl in *. split. eapply closed_upgrade_freef. eassumption. omega.
    split. eapply closed_upgrade_freef. eassumption. omega.
    apply unvv. apply vv in H2. eapply IHn with (H1 := H1); try eassumption; try omega.

  - inversion C. subst. apply vv. rewrite val_type_unfold. destruct vf. destruct i. inversion V. destruct b.
    split; try assumption. split; try assumption. ev. apply unvv. apply vv in H2. simpl in *. eapply IHn; try eassumption;
    try omega.

    split; try assumption. split; try assumption. ev. apply unvv. apply vv in H2. simpl in *. eapply IHn; try eassumption;
    try omega.

    destruct i. ev. split; try assumption. split; try assumption.
    unfold vtsub. intros. destruct (pos iy) eqn : A. specialize (H2 vy iy). rewrite A in H2. intros.
    assert (val_type (vx :: H1) G1 vy T1_1 iy ). apply unvv. apply vv in H3. simpl in *. eapply IHn with (H1 := H1); try eassumption; try omega.
    specialize (H2 H4). apply unvv. apply vv in H2. simpl in *. eapply IHn; try eassumption; try omega.
            specialize (H2 vy iy). rewrite A in H2. intros. assert (val_type (vx :: H1) G1 vy T1_2 iy).
    simpl in *. apply unvv. apply vv in H3. eapply IHn with (H1 := H1); try eassumption; try omega.
    specialize (H2 H4). apply unvv. apply vv in H2. simpl in *. eapply IHn; try eassumption; try omega.

    destruct b; ev. split; try assumption. split; try assumption.
    simpl in *. apply unvv. apply vv in H2. simpl in *. eapply IHn; try eassumption; try omega.
    split; try assumption. split; try assumption.
    simpl in *. apply unvv. apply vv in H2. simpl in *. eapply IHn; try eassumption; try omega.
Qed.



(* used in wf_env_extend and in main theorem *)
Lemma valtp_extend: forall i vx vf H1 T1,
  val_type H1 [] vf T1 i ->
  vtp (vx::H1) [] vf T1 i.
Proof.
  intros. eapply valtp_extend_aux with (H1 := H1). eauto. simpl.
  apply valtp_closed in H. simpl in *. assumption. apply vv in H. assumption.
Qed.

(* used in wf_env_extend *)
Lemma valtp_shrink: forall i vx vf H1 T1,
  val_type (vx::H1) [] vf T1 i ->
  closed 0 0 (length H1) T1 ->
  vtp H1 [] vf T1 i.
Proof.
  intros. apply vv in H. eapply valtp_extend_aux. eauto. simpl. assumption.
  eassumption.
Qed.

Lemma valtp_shrinkM: forall i vx vf H1 GH T1,
  val_type (vx::H1) GH vf T1 i ->
  closed 0 (length GH) (length H1) T1 ->
  vtp H1 GH vf T1 i.
Proof.
  intros. apply vv in H. eapply valtp_extend_aux. eauto. simpl. assumption.
  eassumption.
Qed.

Lemma indexr_hit_high: forall (X:Type) x (jj : X) l1 l2 vf,
  indexr x (l1 ++ l2) = Some vf -> (length l2) <= x ->
  indexr (x + 1) (l1 ++ jj :: l2) = Some vf.
Proof. intros. induction l1. simpl in *. apply indexr_max in H. omega.
  simpl in *. destruct (beq_nat x (length (l1 ++ l2))) eqn : A.
  rewrite beq_nat_true_iff in A. assert (x + 1 = length (l1 ++ l2) + 1).
  omega. rewrite app_length in *. assert(x + 1 = length (l1) + S (length l2)).
  omega. simpl in *. rewrite <- beq_nat_true_iff in H2. rewrite H2. assumption.
  rewrite beq_nat_false_iff in A. assert (x + 1 <> length (l1 ++ l2) + 1).
  omega. rewrite app_length in *. assert(x + 1 <> length (l1) + S (length l2)). omega.
  rewrite <- beq_nat_false_iff in H2. simpl. rewrite H2. apply IHl1. assumption.
Qed.

Lemma indexr_hit_low: forall (X:Type) x (jj : X) l1 l2 vf,
  indexr x (l1 ++ l2) = Some vf -> x < (length l2) ->
  indexr (x) (l1 ++ jj :: l2) = Some vf.
Proof. intros. apply indexr_has in H0. ev. assert (indexr x (l1 ++ l2) = Some x0).
  apply indexr_extend_mult. assumption. rewrite H1 in H. inversion H. subst.
  assert (indexr x (jj :: l2) = Some vf). apply indexr_extend. assumption.
  apply indexr_extend_mult. eassumption.
Qed.

Lemma splice_preserves_size: forall T j,
  tsize_flat T = tsize_flat (splice j T).
Proof.
  intros. induction T; simpl; try rewrite IHT1; try rewrite IHT2; try reflexivity.
  destruct v; simpl; try reflexivity. destruct (le_lt_dec j i); simpl; try reflexivity.
Qed.

Lemma open_permute : forall T V0 V1 i j a b c d,
  closed 0 a b (TSel V0) -> closed 0 c d (TSel V1) -> i <> j ->
  open_rec i V0 (open_rec j V1 T) = open_rec j V1 (open_rec i V0 T).
Proof. intros. generalize dependent i. generalize dependent j.
  induction T; intros.
  simpl. reflexivity.
  simpl. reflexivity.
  simpl. specialize (IHT1 _ _ H1). rewrite IHT1. assert ((S i) <> (S j)) by omega.
  specialize (IHT2 _ _ H2). rewrite IHT2. reflexivity.
  destruct v. simpl. reflexivity. simpl. reflexivity.
  (* varB *)
  destruct (beq_nat i i0) eqn : A. rewrite beq_nat_true_iff in A. subst.
  assert ((open_rec j V1 (TSel (varB i0)) = (TSel (varB i0)))). simpl.
  assert (beq_nat j i0 = false). rewrite beq_nat_false_iff. omega. rewrite H2. reflexivity.
  rewrite H2. simpl. assert (beq_nat i0 i0 = true). erewrite beq_nat_refl. eauto. rewrite H3.
  eapply closed_no_open. eapply closed_upgrade. eauto. omega.
  destruct (beq_nat j i0) eqn : B. rewrite beq_nat_true_iff in B. subst.
  simpl. assert (beq_nat i0 i0 = true). erewrite beq_nat_refl. eauto. rewrite H2.
  assert (beq_nat i i0 = false). rewrite beq_nat_false_iff. omega. rewrite H3.
  assert (TSel (V1) = open_rec i V0 (TSel V1)). eapply closed_no_open. eapply closed_upgrade.
  eapply H0. omega. rewrite <- H4. simpl. rewrite H2. reflexivity.
  assert ((open_rec j V1 (TSel (varB i0))) = TSel (varB i0)). simpl. rewrite B. reflexivity.
  rewrite H2. assert (open_rec i V0 (TSel (varB i0)) = (TSel (varB i0))). simpl.
  rewrite A. reflexivity. rewrite H3. simpl. rewrite B. reflexivity.

  simpl. specialize (IHT1 _ _ H1). rewrite IHT1.
  specialize (IHT2 _ _ H1). rewrite IHT2. reflexivity.
Qed.

Lemma closed_open2: forall i j k V T i1, closed i j k T -> closed i j k (TSel V) ->
  closed i j k (open_rec i1 V T).
Proof.
  intros. generalize dependent i. revert i1.
  induction T; intros; inversion H;
  try econstructor;
  try eapply IHT1; eauto; try eapply IHT2; eauto; try eapply IHT; eauto.
  eapply closed_upgrade. eauto. eauto.
  - (* Case "TVarB". *)
    simpl.
    case_eq (beq_nat i1 x); intros E. eauto.
    econstructor. eapply beq_nat_false_iff in E. omega.
Qed.


Lemma splice_retreat4: forall T i j k m V' V ,
  closed i (j + 1) k (open_rec m V' (splice 0 T)) ->
  (closed i j k (TSel V) -> closed i (j) k (open_rec m V T)).
Proof. induction T; intros; try destruct v; simpl in *.
  constructor.
  constructor.
  inversion H; subst.
  specialize (IHT1 _ _ _ _ _ _ H6 H0). assert (closed (S i) (j) k (TSel V)).
  eapply closed_upgrade. eapply H0. omega.
  specialize (IHT2 _ _ _ _ _ _ H7 H1). constructor. assumption. assumption.
  inversion H. subst. constructor. omega.
  inversion H. subst. constructor. omega.
  destruct (beq_nat m i0) eqn : A. assumption.
    inversion H. subst. constructor. omega.
  inversion H. subst. constructor. eapply IHT1. eassumption. assumption.
  eapply IHT2. eassumption. assumption.
Qed.

Lemma splice_retreat5: forall T i j k m V' V ,
  closed i (j + 1) k (TSel V') -> closed i (j) k (open_rec m V T) ->
  closed i (j + 1) k (open_rec m V' (splice 0 T)).
Proof. induction T; intros; try destruct v; simpl in *.
  constructor.
  constructor.
  inversion H0; subst.
  specialize (IHT1 _ _ _ _ _ _ H H6). assert (closed (S i) (j + 1) k (TSel V')).
  eapply closed_upgrade. eapply H. omega.
  specialize (IHT2 _ _ _ _ _ _ H1 H7). constructor. assumption. assumption.
  inversion H0. subst. constructor. omega.
  inversion H0. subst. constructor. omega.
  destruct (beq_nat m i0) eqn : A. assumption.
    inversion H0. subst. constructor. omega.
  inversion H0. subst. constructor. eapply IHT1. eassumption. eassumption.
  eapply IHT2. eassumption. eassumption.
Qed.


Lemma splice_open_permute0: forall x0 T2 n j,
(open_rec j (varH (n + x0 + 1 )) (splice (x0) T2)) =
(splice (x0) (open_rec j (varH (n + x0)) T2)).
Proof.
  intros x0 T. induction T; intros; simpl; eauto;
  try rewrite IHT1; try rewrite IHT2; try rewrite IHT; eauto;
  destruct v; eauto.

  case_eq (le_lt_dec (x0) i); intros E LE; simpl; eauto.
  rewrite LE. eauto.
  rewrite LE. eauto.
  case_eq (beq_nat j i); intros E; simpl; eauto.
  case_eq (le_lt_dec (x0) (n + x0)); intros EL LE.
  rewrite E. eauto. omega.
  rewrite E. eauto.
Qed.

Lemma indexr_extend_end: forall {X : Type} (jj : X) l x,
  indexr (x + 1) (l ++ [jj]) = indexr x l.
Proof. intros. induction l. simpl. assert (beq_nat (x + 1) 0 = false).
  rewrite beq_nat_false_iff. omega. rewrite H. reflexivity.
  simpl. destruct (beq_nat (x) (length (l))) eqn : A.
  rewrite beq_nat_true_iff in A. assert (x + 1 = length (l ++ [jj])). rewrite app_length. simpl. omega.
  rewrite <- beq_nat_true_iff in H. rewrite H. reflexivity.
  rewrite beq_nat_false_iff in A. assert (x +1 <> length (l ++ [jj])). rewrite app_length. simpl. omega.
  rewrite <- beq_nat_false_iff in H. rewrite H. assumption.
Qed.

Lemma indexr_hit01: forall {X : Type} GH (jj : X),
      indexr 0 (GH ++ [jj]) = Some (jj).
Proof.
  intros X GH. induction GH.
  - intros. simpl. eauto.
  - intros. simpl. destruct (length (GH ++ [jj])) eqn : A.
    rewrite app_length in *. simpl in *. omega.
    apply IHGH.
Qed.


Lemma valtp_splice_aux: forall n T vf H GH1 GH0 jj i,
tsize_flat T < n -> closed 0 (length (GH1 ++ GH0)) (length H) T ->
(
  vtp H (GH1 ++ GH0) vf T i <->
  vtp H (GH1 ++ jj :: GH0) vf (splice (length GH0) T) i
).
Proof.
  induction n; intros ? ? ? ? ? ? ? Sz C. inversion Sz.
  destruct T; split; intros V; apply unvv in V; rewrite val_type_unfold in V;
    assert (length GH1 + S (length GH0) = S(length (GH1 ++ GH0))) as E;
    try rewrite app_length; try omega.
  - apply vv. rewrite val_type_unfold. destruct vf; apply V.
  - apply vv. rewrite val_type_unfold. destruct vf; apply V.
  - apply vv. rewrite val_type_unfold. destruct vf; apply V.
  - apply vv. rewrite val_type_unfold. destruct vf; apply V.
  - destruct vf. destruct i.
    + ev. apply vv. rewrite val_type_unfold. split.
    rewrite app_length. simpl. rewrite E. apply closed_splice. apply H0.
    split. rewrite app_length. simpl. rewrite E. apply closed_splice. apply H1.
    intros. specialize (H2 _ _ H3).
    assert ((forall (vy : vl) (iy : sel),
      if pos iy
      then jj0 vy iy -> val_type H (GH1 ++ GH0) vy T1 iy
      else val_type H (GH1 ++ GH0) vy T1 iy -> jj0 vy iy)).
    { intros. destruct (pos iy) eqn : A. intros. specialize (H4 vy iy). rewrite A in H4. specialize (H4 H6).
      apply unvv. apply vv in H4. simpl in *. eapply IHn; try eassumption; try omega.
      specialize (H4 vy iy).  rewrite A in H4. intros. apply H4. simpl in *. apply unvv. apply vv in H6.
      eapply IHn with (GH0 := GH0); try eassumption; try try omega. }
    specialize (H2 H6 H5). ev. exists x. split; try assumption.
    assert (jj0 ::GH1 ++ jj :: GH0 = (jj0 :: GH1) ++ jj :: GH0) as Eq by apply app_comm_cons.
    unfold open in *. rewrite app_length in *. simpl. rewrite Eq. rewrite splice_open_permute. apply unvv. apply vv in H7.
    eapply IHn with (GH0 := GH0); try eassumption.
    simpl in Sz. rewrite <- open_preserves_size. omega.
    apply closed_open. simpl. eapply closed_upgrade_free.
    apply H1. rewrite app_length. omega.
    constructor. simpl. rewrite app_length. omega.
    + apply vv. rewrite val_type_unfold. simpl. ev. repeat split.
      rewrite app_length. simpl. rewrite E. apply closed_splice. assumption.
      rewrite app_length. simpl. rewrite E. apply closed_splice. assumption. assumption. assumption.

    + apply vv. rewrite val_type_unfold. simpl. ev. repeat split.
      rewrite app_length. simpl. rewrite E. apply closed_splice. assumption.
      rewrite app_length. simpl. rewrite E. apply closed_splice. assumption.
      simpl in H2. rewrite H2. reflexivity. assumption.

  - destruct vf. simpl in V. destruct i.
    + ev. apply vv. rewrite val_type_unfold. inversion C. subst.
    split. assumption. split. assumption. intros.
    specialize (H2 _ _ H3).
    assert ((forall (vy : vl) (iy : sel),
      if pos iy
      then
       jj0 vy iy ->
       val_type H (GH1 ++ jj :: GH0) vy (splice (length GH0) T1) iy
      else
       val_type H (GH1 ++ jj :: GH0) vy (splice (length GH0) T1) iy ->
       jj0 vy iy)).
    { intros. destruct (pos iy) eqn : A. intros. specialize (H4 vy iy). rewrite A in H4. specialize (H4 H6).
      apply unvv. apply vv in H4. simpl in *. eapply IHn with (GH0 := GH0); try eassumption; try omega.
      specialize (H4 vy iy). rewrite A in H4. intros. apply H4. apply unvv. apply vv in H6. simpl in *. eapply IHn;
      try eassumption; try omega. }
    specialize (H2 H6 H5). ev. exists x. split; try assumption. apply unvv. apply vv in H7.
    assert (jj0 ::GH1 ++ jj :: GH0 = (jj0 :: GH1) ++ jj :: GH0) as Eq by apply app_comm_cons.
    unfold open in *. rewrite app_length in *. simpl in *. rewrite splice_open_permute in H7.
    rewrite app_comm_cons. eapply IHn with (GH0 := GH0); try eassumption. simpl in *. rewrite <- open_preserves_size. omega.
    apply closed_open. simpl. eapply closed_upgrade_free. eassumption. rewrite app_length. omega. constructor. simpl. rewrite app_length.
    omega.
    + apply vv. rewrite val_type_unfold. simpl. ev. inversion C. repeat split; assumption.
    + simpl in V. apply vv. rewrite val_type_unfold. simpl. ev. inversion C. repeat split; try assumption.


  - apply vv. rewrite val_type_unfold. destruct vf. simpl in *. destruct v.
    + assumption.
    + destruct (indexr i0 (GH1 ++ GH0)) eqn : B; try solve by inversion.
    destruct (le_lt_dec (length GH0) i0) eqn : A.
    assert (indexr (i0 + 1) (GH1 ++ jj :: GH0) = Some v). apply indexr_hit_high. assumption. omega.
    rewrite H0. apply V. assert (indexr (i0) (GH1 ++ jj :: GH0) = Some v). apply indexr_hit_low. assumption. omega.
    rewrite H0. apply V.
    + inversion V.
    + simpl in *. destruct v; simpl; try apply V.
    destruct (indexr i0 (GH1 ++ GH0)) eqn : B; try solve by inversion.
    destruct (le_lt_dec (length GH0) i0) eqn : A.
    assert (indexr (i0 + 1) (GH1 ++ jj :: GH0) = Some v). apply indexr_hit_high. assumption. omega.
    rewrite H0. apply V. assert (indexr (i0) (GH1 ++ jj :: GH0) = Some v). apply indexr_hit_low. assumption. omega.
    rewrite H0. apply V.

  - apply vv. rewrite val_type_unfold. destruct vf; simpl in *. destruct v.
    + assumption.
    + destruct (le_lt_dec (length GH0) i0) eqn : A. inversion C. subst.
    eapply indexr_has in H4. ev. assert (indexr (i0 + 1)(GH1 ++ jj:: GH0) = Some x). apply indexr_hit_high; assumption.
    rewrite H0. rewrite H1 in V. assumption.
    assert (i0 < length GH0) as H4 by omega. eapply indexr_has in H4. ev. assert (indexr (i0)(GH1 ++ GH0) = Some x).
    apply indexr_extend_mult. assumption. assert (indexr i0 (GH1 ++ jj :: GH0) = Some x). apply indexr_hit_low; assumption.
    rewrite H1. rewrite H2 in V. assumption.
    + inversion V.
    + destruct v; try solve by inversion; try assumption.
    destruct (le_lt_dec (length GH0) i0) eqn : A. inversion C. subst.
    eapply indexr_has in H4. ev. assert (indexr (i0 + 1)(GH1 ++ jj:: GH0) = Some x). apply indexr_hit_high; assumption.
    rewrite H0. rewrite H1 in V. assumption.
    assert (i0 < length GH0) as H4 by omega. eapply indexr_has in H4. ev. assert (indexr (i0)(GH1 ++ GH0) = Some x).
    apply indexr_extend_mult. assumption. assert (indexr i0 (GH1 ++ jj :: GH0) = Some x). apply indexr_hit_low; assumption.
    rewrite H1. rewrite H2 in V. assumption.

  - inversion C. subst. apply vv. rewrite val_type_unfold. destruct vf. simpl in *. destruct i. inversion V. destruct b.
    ev. split. rewrite app_length. simpl. rewrite E. eapply closed_splice. assumption.
    split. rewrite app_length. simpl. rewrite E. eapply closed_splice. assumption.
    apply unvv. eapply IHn with (GH0 := GH0). simpl in *. omega. apply H6. apply vv. assumption.

    ev. split. rewrite app_length. simpl. rewrite E. eapply closed_splice. assumption.
    split. rewrite app_length. simpl. rewrite E. eapply closed_splice. assumption.
    apply unvv. eapply IHn with (GH0 := GH0). simpl in *. omega. assumption. apply vv. assumption.

    simpl in *. destruct i. ev.
    split. rewrite app_length. simpl. rewrite E. eapply closed_splice. assumption.
    split. rewrite app_length. simpl. rewrite E. eapply closed_splice. assumption.
    unfold vtsub. intros. specialize (H2 vy iy). destruct (pos iy) eqn : A. intros. assert (val_type H (GH1 ++ GH0) vy T1 iy).
    apply unvv. apply vv in H3. eapply IHn; try eassumption; try omega. specialize (H2 H4). apply vv in H2.
    apply unvv. apply vv in H4. eapply IHn with (GH0 := GH0); try eassumption; try omega.
    intros. assert (val_type H (GH1 ++ GH0) vy T2 iy). apply unvv. apply vv in H3. eapply IHn; try eassumption; try omega.
    specialize (H2 H4). apply vv in H2. apply unvv. apply vv in H4. eapply IHn with (GH0 := GH0); try eassumption; try omega.

    destruct b; ev. split. rewrite app_length. simpl. rewrite E. eapply closed_splice. assumption.
    split. rewrite app_length. simpl. rewrite E. eapply closed_splice. assumption.
    apply unvv. apply vv in H2. eapply IHn with (GH0 := GH0); try eassumption; try omega.
    split. rewrite app_length. simpl. rewrite E. eapply closed_splice. assumption.
    split. rewrite app_length. simpl. rewrite E. eapply closed_splice. assumption.
    apply unvv. apply vv in H2. eapply IHn with (GH0 := GH0); try eassumption; try omega.

  - inversion C. subst. apply vv. rewrite val_type_unfold. destruct vf. simpl in *. destruct i. inversion V. destruct b.
    split; try assumption. split; try assumption. ev. apply unvv. apply vv in H2. eapply IHn; try eassumption; try omega.
    split; try assumption. split; try assumption. ev. apply unvv. apply vv in H2. eapply IHn; try eassumption; try omega.
    simpl in *. destruct i.
    split; try assumption. split; try assumption. ev. unfold vtsub. intros. specialize (H2 vy iy). destruct (pos iy) eqn : A.
    intros. assert (val_type H (GH1 ++ jj :: GH0) vy (splice (length GH0) T1) iy).
    apply unvv. apply vv in H3. eapply IHn with (GH0 := GH0); try eassumption; try omega.
    specialize (H2 H4). apply vv in H2. apply unvv. eapply IHn; try eassumption; try omega.
    intros. assert (val_type H (GH1 ++ jj :: GH0) vy (splice (length GH0) T2) iy).
    apply unvv. apply vv in H3. eapply IHn with (GH0 := GH0); try eassumption; try omega.
    specialize (H2 H4). apply vv in H2. apply unvv. eapply IHn; try eassumption; try omega.

    destruct b; ev. split; try assumption. split; try assumption. ev.
    apply unvv. apply vv in H2. eapply IHn; try eassumption; try omega.
split; try assumption. split; try assumption. ev.
    apply unvv. apply vv in H2. eapply IHn; try eassumption; try omega.
Qed.


(* used in valtp_widen *)
Lemma valtp_extendH: forall vf H1 GH T1 jj i,
  val_type H1 GH vf T1 i ->
  vtp H1 (jj::GH) vf T1 i.
Proof.
  intros. assert (jj::GH = ([] ++ jj :: GH)). simpl. reflexivity. rewrite H0.
  assert (splice (length GH) T1 = T1). apply valtp_closed in H. eapply closed_splice_idem. eassumption. omega.
  rewrite <- H2.
  eapply valtp_splice_aux with (GH0 := GH). eauto. simpl. apply valtp_closed in H. eapply closed_upgrade_free. eassumption. omega.
  simpl. apply vv in H. assumption.
Qed.

Lemma valtp_shrinkH: forall vf H1 GH T1 jj i,
  val_type H1 (jj::GH) vf T1 i ->
  closed 0 (length GH) (length H1) T1 ->
  vtp H1 GH vf T1 i.
Proof.
  intros.
  assert (vtp H1 ([] ++ GH) vf T1 i <->
  vtp H1 ([] ++ jj :: GH) vf (splice (length GH) T1) i).
  eapply valtp_splice_aux. eauto. simpl. assumption.
  apply H2. simpl. assert (splice (length GH) T1 = T1).
  eapply closed_splice_idem. eassumption. omega. apply vv in H.
  rewrite H3. assumption.
Qed.




(* used in invert_abs *)
Lemma vtp_subst1: forall venv jj v T2,
  val_type venv [jj] v (open (varH 0) T2) nil ->
  closed 0 0 (length venv) T2 ->
  val_type venv [] v T2 nil.
Proof.
  intros. assert (open (varH 0) T2 = T2). symmetry. unfold open.
  eapply closed_no_open. eapply H0. rewrite H1 in H.
  apply unvv. eapply valtp_shrinkH. simpl. eassumption. assumption.
Qed.

Lemma vtp_subst2_aux: forall n T venv jj v x i GH j k,
  tsize_flat T < n ->
  closed j (length GH) (length venv) T -> k < j ->
  indexr x venv = Some jj ->
  (vtp venv (GH ++ [jj]) v (open_rec k (varH 0) (splice 0 T)) i <->
   vtp venv GH v (open_rec k (varF x) T) i).
Proof. induction n; intros ? ? ? ? ? ? ? ? ? Sz Cz Bd Id. inversion Sz.
  destruct T; split; intros V; apply unvv in V; rewrite val_type_unfold in V.
  - unfold open. simpl in *. apply vv. rewrite val_type_unfold. destruct v; apply V.
  - unfold open. simpl in *. apply vv. rewrite val_type_unfold. destruct v; apply V.
  - unfold open. simpl in *. apply vv. rewrite val_type_unfold. destruct v; apply V.
  - unfold open. simpl in *. apply vv. rewrite val_type_unfold. destruct v; apply V.
  - inversion Cz. subst.
    unfold open in *. simpl in *. apply vv. rewrite val_type_unfold in *. destruct v.
    destruct i.
    + ev. split. {rewrite app_length in *.  simpl in *. eapply splice_retreat4.
    eassumption. constructor. eapply indexr_max. eassumption. }
    split. { rewrite app_length in *. simpl in *. eapply splice_retreat4.
    eassumption. constructor. eapply indexr_max. eassumption. }

    intros. specialize (H1 _ _ H2). assert ((forall (vy : vl) (iy : sel),
      if pos iy
      then
       jj0 vy iy ->
       val_type venv0 (GH ++ [jj]) vy (open_rec k (varH 0) (splice 0 T1)) iy
      else
       val_type venv0 (GH ++ [jj]) vy (open_rec k (varH 0) (splice 0 T1)) iy ->
       jj0 vy iy)).
    { intros. destruct (pos  iy) eqn : A. specialize (H3 vy iy). rewrite A in H3. intros.
      specialize (H3 H7). apply unvv. apply vv in H3. eapply IHn; try eassumption; try omega.
      specialize (H3 vy iy). rewrite A in H3. intros. apply H3. apply unvv. apply vv in H7.
      eapply IHn; try eassumption; try omega. }
    specialize (H1 H7 H6). ev. exists x0. split. assumption. apply unvv. apply vv in H8.
    assert (jj0 :: GH ++ [jj] = (jj0 :: GH) ++ [jj]) as Eq.
    apply app_comm_cons. rewrite Eq in H8.
    unfold open.
    erewrite open_permute in H8. erewrite open_permute.
    assert ((open_rec 0 (varH (length (GH ++ [jj]))) (splice 0 T2)) =
             splice 0 (open_rec 0 (varH (length GH)) T2)). {
    rewrite app_length. simpl.
    assert ((length GH) = (length GH) + 0). omega. rewrite H9.
    apply (splice_open_permute0 0 T2 (length GH) 0).
    }
    rewrite H9 in H8.
    eapply IHn with (GH := (jj0::GH)). erewrite <- open_preserves_size. omega.
    assert (closed (S j) (S (length GH)) (length venv0) T2). eapply closed_upgrade_free.
    eassumption. omega. eapply closed_open2. eassumption. constructor. simpl. omega. omega.
    eapply Id. apply H8. constructor. eauto. constructor. eauto. omega.
    constructor. eauto. constructor. eauto. omega.
    + rewrite app_length in V. simpl in V. ev. repeat split.
      eapply splice_retreat4. eassumption. constructor. eapply indexr_max. eassumption.
      eapply splice_retreat4. eassumption. constructor. eapply indexr_max. eassumption.
      eauto. eauto.
    + rewrite app_length in V. simpl in V. ev. repeat split.
      eapply splice_retreat4. eassumption. constructor. eapply indexr_max. eassumption.
      eapply splice_retreat4. eassumption. constructor. eapply indexr_max. eassumption.
      eauto. eauto.


  - inversion Cz. subst.
    unfold open in *. simpl in *. apply vv. rewrite val_type_unfold in *. destruct v.
    destruct i.
    + ev. split. { rewrite app_length. simpl. eapply splice_retreat5. constructor. omega.
    eassumption. }
    split. { rewrite app_length. simpl. eapply splice_retreat5. constructor.
    omega. eassumption. }
    intros. specialize (H1 _ _ H2). assert ((forall (vy : vl) (iy : sel),
      if pos iy
      then jj0 vy iy -> val_type venv0 GH vy (open_rec k (varF x) T1) iy
      else val_type venv0 GH vy (open_rec k (varF x) T1) iy -> jj0 vy iy)).
    { intros. destruct (pos  iy) eqn : A. specialize (H3 vy iy). rewrite A in H3. intros.
      specialize (H3 H7). apply unvv. apply vv in H3. eapply IHn; try eassumption; try omega.
      specialize (H3 vy iy). rewrite A in H3. intros. apply H3. apply unvv. apply vv in H7.
      eapply IHn; try eassumption; try omega. }
    specialize (H1 H7 H6). ev. exists x0. split. assumption. apply unvv. apply vv in H8.
    assert (jj0 :: GH ++ [jj] = (jj0 :: GH) ++ [jj]) as Eq.
    apply app_comm_cons. rewrite Eq. unfold open in *.
    erewrite open_permute in H8. erewrite open_permute.
    assert ((open_rec 0 (varH (length (GH ++ [jj]))) (splice 0 T2)) =
             splice 0 (open_rec 0 (varH (length GH)) T2)). {
    rewrite app_length. simpl.
    assert ((length GH) = (length GH) + 0). omega. rewrite H9.
    apply (splice_open_permute0 0 T2 (length GH) 0).
    }
    rewrite H9.
    eapply IHn with (GH := (jj0::GH)). erewrite <- open_preserves_size. omega.
    assert (closed (S j) (S (length GH)) (length venv0) T2). eapply closed_upgrade_free.
    eassumption. omega. eapply closed_open2. eassumption. constructor. simpl. omega. omega.
    eapply Id. apply H8. constructor. eauto. constructor. eauto. omega.
    constructor. eauto. constructor. eauto. omega.
    + ev. rewrite app_length. simpl. repeat split.
      eapply splice_retreat5. constructor. omega. eauto.
      eapply splice_retreat5. constructor. omega. eauto.
      eauto. eauto.
    + ev. rewrite app_length. simpl. repeat split.
      eapply splice_retreat5. constructor. omega. eauto.
      eapply splice_retreat5. constructor. omega. eauto.
      eauto. eauto.

  - unfold open in *. simpl in *. apply vv. rewrite val_type_unfold in *.
    destruct v; destruct v0; simpl in *; try apply V.
    + assert (indexr (i0 + 1) (GH ++ [jj]) = indexr i0 GH). {
    apply indexr_extend_end. }
    rewrite H in V. apply V.
    + destruct (beq_nat k i0) eqn : A.
    simpl in *. assert (indexr 0 (GH ++ [jj]) = Some jj).
    apply indexr_hit01.
    rewrite H in V. rewrite Id. apply V. inversion V.
    + assert (indexr (i0 + 1) (GH ++ [jj]) = indexr i0 GH). apply indexr_extend_end.
    rewrite H in V. apply V.
    + destruct (beq_nat k i0) eqn : A.
    simpl in *. assert (indexr 0 (GH ++ [jj]) = Some jj). apply indexr_hit01.
    rewrite H in V. rewrite Id. apply V. inversion V.

  - unfold open in *. simpl in *. apply vv. rewrite val_type_unfold in *.
    destruct v; destruct v0; simpl in *; try apply V.
    assert (indexr (i0 + 1) (GH ++ [jj]) = indexr i0 GH). apply indexr_extend_end.
    rewrite H. apply V.
    destruct (beq_nat k i0) eqn : A.
    simpl in *. assert (indexr 0 (GH ++ [jj]) = Some jj). apply indexr_hit01.
    rewrite H. rewrite Id in V. apply V. inversion V.
    assert (indexr (i0 + 1) (GH ++ [jj]) = indexr i0 GH). apply indexr_extend_end.
    rewrite H. apply V.
    destruct (beq_nat k i0) eqn : A.
    simpl in *. assert (indexr 0 (GH ++ [jj]) = Some jj). apply indexr_hit01.
    rewrite H. rewrite Id in V. apply V. inversion V.

  - inversion Cz. subst.
    unfold open in *. simpl in *. apply vv. rewrite val_type_unfold in *. destruct i.
    + destruct v; try solve by inversion. ev. rewrite app_length in *. split. { eapply splice_retreat4.
      simpl in *. eassumption. constructor. apply indexr_max in Id. omega. } split. { eapply splice_retreat4.
      simpl in *. eassumption. constructor. apply indexr_max in Id. omega. }
    unfold vtsub. intros. specialize (H1 vy iy). destruct (pos iy). intros. assert (
    val_type venv0 (GH ++ [jj]) vy (open_rec k (varH 0) (splice 0 T1)) iy).
    apply vv in H2. apply unvv. eapply IHn; try eassumption; try omega. specialize (H1 H3). apply vv in H1.
    apply unvv. eapply IHn; try eassumption; try omega.
    intros. assert (
    val_type venv0 (GH ++ [jj]) vy (open_rec k (varH 0) (splice 0 T2)) iy).
    apply vv in H2. apply unvv. eapply IHn; try eassumption; try omega. specialize (H1 H3). apply vv in H1.
    apply unvv. eapply IHn; try eassumption; try omega.

    + rewrite app_length in *. destruct v. destruct b. ev. split. eapply splice_retreat4. eassumption. constructor. eapply indexr_max.
    eassumption. split. eapply splice_retreat4. eassumption. constructor. eapply indexr_max.
    eassumption.
    apply vv in H1. apply unvv. eapply IHn; try eassumption; try omega.
    ev. split. eapply splice_retreat4. eassumption. constructor. eapply indexr_max.
    eassumption. split. eapply splice_retreat4. eassumption. constructor. eapply indexr_max.
    eassumption.
    apply vv in H1. apply unvv. eapply IHn; try eassumption; try omega.
    destruct b; ev. split. eapply splice_retreat4. eassumption. constructor. eapply indexr_max. eassumption.
    split. eapply splice_retreat4. eassumption. constructor. eapply indexr_max. eassumption.
    apply unvv. apply vv in H1. eapply IHn; try eassumption; try omega.
    split. eapply splice_retreat4. eassumption. constructor. eapply indexr_max. eassumption.
    split. eapply splice_retreat4. eassumption. constructor. eapply indexr_max. eassumption.
    apply unvv. apply vv in H1. eapply IHn; try eassumption; try omega.

  - inversion Cz. subst.
    unfold open in *. simpl in *. apply vv. rewrite val_type_unfold in *. destruct i.
    + destruct v; try solve by inversion. ev. rewrite app_length in *. split. { eapply splice_retreat5.
      constructor. omega. eassumption. }
    split. eapply splice_retreat5. constructor. omega. eassumption.
    unfold vtsub. intros. specialize (H1 vy iy). destruct (pos iy). intros. assert (val_type venv0 GH vy (open_rec k (varF x) T1) iy).
    apply vv in H2. apply unvv. eapply IHn; try eassumption; try omega. specialize (H1 H3). apply vv in H1.
    apply unvv. eapply IHn; try eassumption; try omega.
    intros. assert (val_type venv0 GH vy (open_rec k (varF x) T2) iy).
    apply unvv. apply vv in H2. eapply IHn; try eassumption; try omega. specialize (H1 H3). apply vv in H1.
    apply unvv. eapply IHn; try eassumption; try omega.

    + rewrite app_length. simpl in *. destruct v. ev. destruct b; ev.
    split. eapply splice_retreat5. constructor. omega. eassumption.
    split. eapply splice_retreat5. constructor. omega. eassumption.
    apply unvv. apply vv in H1. eapply IHn; try eassumption; try omega.
    ev. split. eapply splice_retreat5. constructor. omega. eassumption.
    split. eapply splice_retreat5. constructor. omega. eassumption.
    apply unvv. apply vv in H1. eapply IHn; try eassumption; try omega.
    destruct b; ev. split. eapply splice_retreat5. constructor. omega. eassumption.
    split. eapply splice_retreat5. constructor. omega. eassumption.
    apply unvv. apply vv in H1. eapply IHn; try eassumption; try omega.
    split. eapply splice_retreat5. constructor. omega. eassumption.
    split. eapply splice_retreat5. constructor. omega. eassumption.
    apply unvv. apply vv in H1. eapply IHn; try eassumption; try omega.


Grab Existential Variables.
apply 0. apply 0. apply 0. apply 0.
apply 0. apply 0. apply 0. apply 0.
Qed.


Lemma vtp_subst: forall T venv jj v x i GH,
  closed 1 (length GH) (length venv) T ->
  indexr x venv = Some jj ->
  (vtp venv (GH ++ [jj]) v (open (varH 0) (splice 0 T)) i <->
   vtp venv GH v (open (varF x) T) i).
Proof. intros. eapply vtp_subst2_aux. eauto. eassumption. omega. assumption. Qed.


(* used in invert_dabs *)
Lemma vtp_subst2: forall venv jj v x T2,
  closed 1 0 (length venv) T2 ->
  val_type venv [jj] v (open (varH 0) T2) nil ->
  indexr x venv = Some jj ->
  val_type venv [] v (open (varF x) T2) nil.
Proof.
  intros. apply vv in H0. assert ([jj] = ([] ++ [jj])). simpl. reflexivity.
  rewrite H2 in H0. assert (splice 0 T2 = T2). eapply closed_splice_idem.
  eassumption. omega. rewrite <- H3 in H0. eapply vtp_subst in H0. apply unvv. eassumption.
  simpl. assumption. assumption.
Qed.

(* used in vabs case of main theorem *)
Lemma vtp_subst3: forall venv jj v T2,
  closed 1 0 (length venv) T2 ->
  val_type (jj::venv) [] v (open (varF (length venv)) T2) nil ->
  val_type venv [jj] v (open (varH 0) T2) nil.
Proof.
  intros. apply unvv. assert (splice 0 T2 = T2) as EE. eapply closed_splice_idem. eassumption. omega.
  assert (vtp (jj::venv0) ([] ++ [jj]) v (open (varH 0) (splice 0 T2)) nil).
  assert (indexr (length venv0) (jj :: venv0) = Some jj). simpl.
    replace (beq_nat (length venv0) (length venv0) ) with true. reflexivity.
    apply beq_nat_refl.
  eapply vtp_subst. simpl. eapply closed_upgrade_freef. eassumption. omega. eassumption.
  apply vv. assumption.
  simpl in *. rewrite EE in H1. eapply valtp_shrinkM. apply unvv. eassumption.
  apply closed_open. simpl. eapply closed_upgrade_free. eassumption. omega.
  constructor. simpl. omega.
Qed.


(* ### Relating Value Typing and Subtyping ### *)
Lemma valtp_widen_aux: forall G1 GH1 T1 T2,
  stp G1 GH1 T1 T2 ->
  forall (H: list vset) GH,
    length G1 = length H ->
    (forall x TX, indexr x G1 = Some TX ->
                   exists vx jj,
                     indexr x H = Some jj /\
                     jj vx nil /\
                     vtsub jj (fun vy iy => vtp H GH vy TX iy) /\
                     good_bounds jj) ->
    length GH1 = length GH ->
    (forall x TX, indexr x GH1 = Some TX ->
                   exists vx jj,
                     indexr x GH = Some jj /\
                     jj vx nil /\
                     vtsub jj (fun vy iy => vtp H GH vy TX iy) /\
                     good_bounds jj) ->
  vtsub (fun vf i => vtp H GH vf T1 i) (fun vf i => vtp H GH vf T2 i).
Proof.
  intros ? ? ? ? stp.
  induction stp; intros G GHX LG RG LGHX RGHX vf i;
  remember (pos i) as p; destruct p; intros V0; eapply unvv in V0.
  - (* Case "Top". *)
    eapply vv. rewrite val_type_unfold. destruct vf; rewrite Heqp; reflexivity.
  - rewrite val_type_unfold in V0. simpl in V0. rewrite <-Heqp in V0. destruct vf; inversion V0.
  - (* Case "Bot". *)
    rewrite val_type_unfold in V0. destruct vf; rewrite <-Heqp in V0; inversion V0.
  - eapply vv. rewrite val_type_unfold. rewrite <-Heqp. destruct vf; reflexivity.
  - (* Case "mem". *)
    subst.
    rewrite val_type_unfold in V0.
    eapply vv. rewrite val_type_unfold.
    destruct vf; destruct i; try destruct b; try solve by inversion; ev.
    + rewrite <-LG. rewrite <-LGHX. split.
      apply stp_closed1 in stp2. assumption. split. apply stp_closed2 in stp1. assumption.
      simpl in Heqp. specialize (IHstp1 _ _ LG RG LGHX RGHX (vabs l t t0) i).
      apply unvv. rewrite <- Heqp in IHstp1. eapply IHstp1. eapply vv. assumption.
    + rewrite <-LG. rewrite <-LGHX. split.
      apply stp_closed1 in stp2. assumption. split. apply stp_closed2 in stp1. assumption.
      simpl in Heqp. destruct (pos i) eqn : A. apply unvv. inversion Heqp.
      specialize (IHstp2 _ _ LG RG LGHX RGHX (vabs l t t0) i). rewrite A in IHstp2.
      apply unvv. eapply IHstp2. eapply vv. assumption.

    + rewrite<-LG. rewrite <-LGHX. split.
      apply stp_closed1 in stp2. assumption. split. apply stp_closed2 in stp1. assumption.
      unfold vtsub. intros. specialize (H1 vy iy).
      specialize (IHstp1 _ _ LG RG LGHX RGHX vy iy).
      specialize (IHstp2 _ _ LG RG LGHX RGHX vy iy).
      destruct (pos iy) eqn : A. intros. eapply vv in H2. specialize (IHstp2 H2). apply unvv in IHstp2.
      specialize (H1 IHstp2). eapply vv in H1. specialize (IHstp1 H1). apply unvv. assumption.
      intros. eapply vv in H2. specialize (IHstp1 H2). apply unvv in IHstp1.
      specialize (H1 IHstp1). eapply vv in H1. specialize (IHstp2 H1). apply unvv. assumption.

    + rewrite<-LG. rewrite <-LGHX.  ev. split.
      apply stp_closed1 in stp2. assumption. split. apply stp_closed2 in stp1. assumption.
      simpl in Heqp. specialize (IHstp1 _ _ LG RG LGHX RGHX (vty l t) i).
      apply unvv. rewrite <- Heqp in IHstp1. eapply IHstp1. eapply vv. assumption.
    + rewrite <-LG. rewrite <-LGHX.  ev. split.
      apply stp_closed1 in stp2. assumption. split. apply stp_closed2 in stp1. assumption.
      simpl in Heqp. specialize (IHstp1 _ _ LG RG LGHX RGHX (vty l t) i).
      apply unvv. destruct (pos i) eqn : A. inversion Heqp.
      specialize (IHstp2 _ _ LG RG LGHX RGHX (vty l t) i).
      rewrite A in IHstp2. eapply IHstp2. eapply vv. assumption.

  - subst.
    rewrite val_type_unfold in V0.
    eapply vv. rewrite val_type_unfold.
    destruct vf; destruct i; try destruct b; try solve by inversion; ev.
    + rewrite <- LG. rewrite <- LGHX.  ev. split.
      apply stp_closed2 in stp2. assumption. split. apply stp_closed1 in stp1. assumption.
      simpl in Heqp. specialize (IHstp1 _ _ LG RG LGHX RGHX (vabs l t t0) i).
      apply unvv. rewrite <- Heqp in IHstp1. eapply IHstp1. eapply vv. assumption.
    + rewrite <- LG. rewrite <- LGHX.  ev. split.
      apply stp_closed2 in stp2. assumption. split. apply stp_closed1 in stp1. assumption.
      simpl in Heqp. specialize (IHstp1 _ _ LG RG LGHX RGHX (vabs l t t0) i).
      apply unvv. destruct (pos i) eqn : A.
      specialize (IHstp2 _ _ LG RG LGHX RGHX (vabs l t t0) i).
      rewrite A in IHstp2. eapply IHstp2. eapply vv. assumption.  inversion Heqp.
    +  rewrite <- LG. rewrite <- LGHX.  ev. split.
      apply stp_closed2 in stp2. assumption. split. apply stp_closed1 in stp1. assumption.
      simpl in Heqp. specialize (IHstp1 _ _ LG RG LGHX RGHX (vty l t) i).
      apply unvv. rewrite <- Heqp in IHstp1. eapply IHstp1. eapply vv. assumption.
    +  rewrite <- LG. rewrite <- LGHX.  ev. split.
      apply stp_closed2 in stp2. assumption. split. apply stp_closed1 in stp1. assumption.
      simpl in Heqp. specialize (IHstp1 _ _ LG RG LGHX RGHX (vty l t) i).
      apply unvv. destruct (pos i) eqn : A.
      specialize (IHstp2 _ _ LG RG LGHX RGHX (vty l t) i).
      rewrite A in IHstp2. eapply IHstp2. eapply vv. assumption.  inversion Heqp.

  - (* Case "Sel1". *)
    subst. specialize (IHstp _ _ LG RG LGHX RGHX).
    rewrite val_type_unfold in V0.
    specialize (RG _ _ H).
    ev. rewrite H1 in V0.
    assert (x1 vf (ub :: i)). destruct vf; eauto. clear V0.
    assert (vtp G GHX vf TX (ub :: i)). specialize (H3 vf (ub :: i)). simpl in H3.
    rewrite <- Heqp in H3. eapply H3. assumption.
    assert (vtp G GHX vf (TMem TBot T2) (ub :: i)).
    specialize(IHstp vf (ub :: i)). simpl in IHstp.
    rewrite <- Heqp in IHstp.
    eapply IHstp. assumption.

    eapply unvv in H7. rewrite val_type_unfold in H7.
    destruct vf; eapply vv; apply H7.
  - eapply vv. rewrite val_type_unfold.
    remember RG as ENV. clear HeqENV.
    specialize (RG _ _ H).
    ev. rewrite H1.
    assert (vtp G GHX vf (TMem TBot T2) (ub :: i)). eapply vv. rewrite val_type_unfold. destruct vf.
    split. constructor. split. eapply valtp_closed; eassumption. assumption.
    split. constructor. split. eapply valtp_closed; eassumption. assumption.
    assert (vtp G GHX vf TX (ub :: i)).
    specialize (IHstp _ _ LG ENV LGHX RGHX vf (ub :: i)). simpl in IHstp. rewrite <-Heqp in IHstp. eapply IHstp. assumption.
    assert (x1 vf (ub :: i)).
    specialize (H3 vf (ub :: i)). simpl in H3. rewrite <-Heqp in H3. eapply H3. assumption.
    destruct vf; assumption.
  - (* Case "Sel2". *)
    eapply vv. rewrite val_type_unfold.
    remember RG as ENV. clear HeqENV.
    specialize (RG _ _ H).
    ev. rewrite H1.
    assert (vtp G GHX vf (TMem T1 TTop) (lb :: i)). eapply vv. rewrite val_type_unfold. destruct vf.
    split. eapply valtp_closed; eassumption. split. constructor. assumption.
    split. eapply valtp_closed; eassumption. split. constructor. assumption.
    assert (vtp G GHX vf TX (lb :: i)).
    specialize (IHstp _ _ LG ENV LGHX RGHX vf (lb :: i)). simpl in IHstp. rewrite <-Heqp in IHstp. eapply IHstp. assumption.
    assert (x1 vf (lb :: i)).
    specialize (H3 vf (lb :: i)). simpl in H3. rewrite <-Heqp in H3. eapply H3. assumption.
    assert (x1 vf (ub :: i)). specialize (H4 x0 [] H2 vf i). rewrite <-Heqp in H4. simpl in H4. eapply H4. assumption.
    destruct vf; assumption.
  - subst.
    rewrite val_type_unfold in V0.
    remember RG as ENV. clear HeqENV.
    specialize (RG _ _ H).
    ev. rewrite H1 in V0.
    assert (x1 vf (ub :: i)). destruct vf; eauto. clear V0.
    assert (x1 vf (lb :: i)). specialize (H4 x0 [] H2 vf i). rewrite <-Heqp in H4.
    simpl in *. eapply H4. assumption.
    assert (vtp G GHX vf TX (lb :: i)). specialize (H3 vf (lb :: i)). simpl in H3. rewrite <-Heqp in H3. eapply H3. assumption.
    assert (vtp G GHX vf (TMem T1 TTop) (lb :: i)).
    specialize (IHstp _ _ LG ENV LGHX RGHX vf (lb :: i)). simpl in IHstp. rewrite <-Heqp in IHstp.
    eapply IHstp. assumption.

    eapply unvv in H8. rewrite val_type_unfold in H8.
    destruct vf; eapply vv; apply H8.

  - (* Case "selx". *)
    eapply vv. eapply V0.
  - eapply vv. eapply V0.

  (* exactly the same as sel1/sel2, modulo RG/RGHX *)
  - (* Case "Sel1". *)
    subst.
    rewrite val_type_unfold in V0.
    remember RGHX as ENV. clear HeqENV.
    specialize (RGHX _ _ H).
    ev. rewrite H1 in V0.
    assert (x1 vf (ub :: i)). destruct vf; eauto. clear V0.
    assert (vtp G GHX vf TX (ub :: i)). specialize (H3 vf (ub :: i)). simpl in H3. rewrite <-Heqp in H3. eapply H3. assumption.
    assert (vtp G GHX vf (TMem TBot T2) (ub :: i)).
    specialize (IHstp _ _ LG RG LGHX ENV vf (ub :: i)). simpl in IHstp. rewrite <-Heqp in IHstp.
    eapply IHstp. assumption.

    eapply unvv in H7. rewrite val_type_unfold in H7.
    destruct vf; eapply vv; apply H7.
  - eapply vv. rewrite val_type_unfold.
    remember RGHX as ENV. clear HeqENV.
    specialize (RGHX _ _ H).
    ev. rewrite H1.
    assert (vtp G GHX vf (TMem TBot T2) (ub :: i)). eapply vv. rewrite val_type_unfold. destruct vf.
    split. constructor. split. eapply valtp_closed. eassumption. assumption.
    split. constructor. split. eapply valtp_closed. eassumption. assumption.
    assert (vtp G GHX vf TX (ub :: i)).
    specialize (IHstp _ _ LG RG LGHX ENV vf (ub :: i)). simpl in IHstp. rewrite <-Heqp in IHstp. eapply IHstp. assumption.
    assert (x1 vf (ub :: i)).
    specialize (H3 vf (ub :: i)). simpl in H3. rewrite <-Heqp in H3. eapply H3. assumption.
    destruct vf; assumption.
  - (* Case "Sel2". *)
    eapply vv. rewrite val_type_unfold.
    remember RGHX as ENV. clear HeqENV.
    specialize (RGHX _ _ H).
    ev. rewrite H1.
    assert (vtp G GHX vf (TMem T1 TTop) (lb :: i)). eapply vv. rewrite val_type_unfold. destruct vf.
    split. eapply valtp_closed. eassumption. split. constructor. assumption.
    split. eapply valtp_closed. eassumption. split. constructor. assumption.
    assert (vtp G GHX vf TX (lb :: i)).
    specialize (IHstp _ _ LG RG LGHX ENV vf (lb :: i)). simpl in IHstp. rewrite <-Heqp in IHstp. eapply IHstp. assumption.
    assert (x1 vf (lb :: i)).
    specialize (H3 vf (lb :: i)). simpl in H3. rewrite <-Heqp in H3. eapply H3. assumption.
    assert (x1 vf (ub :: i)). specialize (H4 x0 [] H2 vf i). rewrite <-Heqp in H4.
    simpl in *. eapply H4. assumption.
    destruct vf; assumption.
   - subst.
    rewrite val_type_unfold in V0.
    remember RGHX as ENV. clear HeqENV.
    specialize (RGHX _ _ H).
    ev. rewrite H1 in V0.
    assert (x1 vf (ub :: i)). destruct vf; eauto. clear V0.
    assert (x1 vf (lb :: i)). specialize (H4 x0 [] H2 vf i). rewrite <-Heqp in H4.
    simpl in *. eapply H4. assumption.
    assert (vtp G GHX vf TX (lb :: i)). specialize (H3 vf (lb :: i)). simpl in H3. rewrite <-Heqp in H3. eapply H3. assumption.
    assert (vtp G GHX vf (TMem T1 TTop) (lb :: i)).
    specialize (IHstp _ _ LG RG LGHX ENV vf (lb :: i)). simpl in IHstp. rewrite <-Heqp in IHstp.
    eapply IHstp. assumption.

    eapply unvv in H8. rewrite val_type_unfold in H8.
    destruct vf; eapply vv; apply H8.


  - (* Case "selax". *)
    eapply vv. eapply V0.
  - eapply vv. eapply V0.

  - (* Case "Fun". *)
    subst.
    rewrite val_type_unfold in V0.
    apply vv. rewrite val_type_unfold.
    subst. destruct vf; destruct i; try solve [inversion V0].
    destruct V0 as [? [? LR]].
    assert (closed 0 (length GHX) (length G) T3). rewrite <-LG. rewrite <-LGHX. eapply stp_closed in stp1. eapply stp1.
    assert (closed 1 (length GHX) (length G) T4). rewrite <-LG. rewrite <-LGHX. eapply H1.
    split. eauto. split. eauto.
    (* try to use LR for the goal, with help of the inductive hypothesis *)
    intros vx jj VST0 STJ STB.
    specialize (IHstp1 _ _ LG RG LGHX RGHX).
    assert (vtsub jj (fun vy iy => val_type G GHX vy T1 iy)) as STJ1.
    { intros vy iy. specialize (STJ vy iy).
      remember (pos iy) as p. destruct p.
      specialize (IHstp1 vy iy). rewrite <-Heqp0 in IHstp1.
      intros. eapply unvv. eapply IHstp1. eapply vv. eapply STJ. assumption.
      specialize (IHstp1 vy iy). rewrite <-Heqp0 in IHstp1.
      intros. eapply STJ. eapply unvv. eapply IHstp1. eapply vv. assumption. }
    destruct (LR vx jj VST0 STJ1 STB) as [v [TE VT]].
    exists v. split. eapply TE. eapply unvv.

    (* now deal with function result! try to use inductive hypothesis2 *)
    rewrite <-LGHX. rewrite <-LGHX in VT.

    (* broaden goal so that we can directly assert for hypothesis2 *)
    assert (if pos nil then
      vtp G (jj :: GHX) v (open (varH (length GH)) T2) nil ->
      vtp G (jj :: GHX) v (open (varH (length GH)) T4) nil
    else
      vtp G (jj :: GHX) v (open (varH (length GH)) T4) nil ->
      vtp G (jj :: GHX) v (open (varH (length GH)) T2) nil) as ST2. {

    eapply IHstp2. eapply LG.

    (* extend RG *)
    intros ? ? IX. destruct (RG _ _ IX) as [vx0 [jj0 [IX1 [VJ0 [FA FAB]]]]].
    (* just for a closed later *)
    assert (vtp G GHX vx0 TX nil). specialize (FA vx0 nil). simpl in FA. eapply FA. assumption.
    exists vx0. exists jj0. split. eapply IX1. split. assumption. split.
    unfold vtsub. intros.
    (* jj -> val_type *) specialize (FA vy iy).
    remember (pos iy) as p. destruct p.
    intros. eapply valtp_extendH. eapply unvv. eapply FA. assumption.
    intros. eapply FA. eapply valtp_shrinkH. eapply unvv. eassumption.
    (* the close that I mentioned before *)
    eapply valtp_closed. eapply unvv. eassumption.
    (* jj lb -> jj ub *) apply FAB.

    (* extend LGHX *)
    simpl. rewrite LGHX. reflexivity.

    (* extend RGHX *)
    intros ? ? IX.
    { case_eq (beq_nat x (length GHX)); intros E.
      + simpl in IX. rewrite LGHX in IX. rewrite E in IX. inversion IX. subst TX.
        exists vx. exists jj. split. simpl. rewrite E. reflexivity.
        split. assumption. split.
        unfold vtsub. intros. specialize (STJ vy iy). remember (pos iy) as p. destruct p; intros.
        eapply valtp_extendH. eapply STJ. assumption.
        eapply STJ. eapply unvv. eapply valtp_shrinkH. eapply unvv. eassumption.
        assumption. assumption.
      + assert (indexr x GH = Some TX) as IX0.
        simpl in IX. rewrite LGHX in IX. rewrite E in IX. inversion IX. reflexivity.
        specialize (RGHX _ _ IX0). ev.
        (* for closed later *)
        assert (vtp G GHX x0 TX nil). specialize (H7 x0 nil). simpl in H7. eapply H7. assumption.        exists x0.
        exists x1. split. simpl. rewrite E. eapply H5. split. assumption. split.
        unfold vtsub. intros. specialize (H7 vy iy). remember (pos iy) as p. destruct p; intros.
        eapply valtp_extendH. eapply unvv. eapply H7. assumption.
        eapply H7. eapply valtp_shrinkH. eapply unvv. eassumption.
        (* the close mentioned above *)
        eapply valtp_closed. eapply unvv. eassumption.
        assumption.
    }

    }
    simpl in ST2. eapply ST2. eapply vv. eapply VT.

    eapply stp_closed1 in stp1. rewrite <-LG. rewrite <-LGHX. ev. repeat split; assumption.
    eapply stp_closed1 in stp1. rewrite <-LG. rewrite <-LGHX. ev. repeat split; assumption.
    eapply stp_closed1 in stp1. rewrite <-LG. rewrite <-LGHX. ev. repeat split; assumption.

  - rewrite val_type_unfold in V0. rewrite <-Heqp in V0.
    destruct vf; destruct i; inversion Heqp.
    simpl in Heqp; inversion Heqp.
    ev. inversion H6.
    ev. inversion H5.

  - (* Case "trans". *)
    specialize (IHstp1 _ _ LG RG LGHX RGHX vf i).
    specialize (IHstp2 _ _ LG RG LGHX RGHX vf i).
    rewrite <-Heqp in *.
    eapply IHstp2. eapply IHstp1. eapply vv. eapply V0.
  - specialize (IHstp1 _ _ LG RG LGHX RGHX vf i).
    specialize (IHstp2 _ _ LG RG LGHX RGHX vf i).
    rewrite <-Heqp in *.
    eapply IHstp1. eapply IHstp2. eapply vv. eapply V0.
Qed.


Lemma valtp_widen: forall vf GH H G1 T1 T2,
  val_type GH [] vf T1 nil ->
  stp G1 [] T1 T2 ->
  R_env H GH G1 ->
  vtp GH [] vf T2 nil.
Proof.
  intros.
  assert (forall (vf0 : vl) (i : sel),
    if pos i
    then vtp GH [] vf0 T1 i -> vtp GH [] vf0 T2 i
    else vtp GH [] vf0 T2 i -> vtp GH [] vf0 T1 i).
  eapply valtp_widen_aux. eassumption. destruct H2 as [L1 [L2 ?]]. omega.
  { intros. destruct H2 as [L1 [L2 A]]. specialize (A _ _ H3). ev.
    eexists. eexists. repeat split; try eassumption. }
  reflexivity.
  { intros. simpl in H3. inversion H3. }
  specialize (H3 vf nil). simpl in H3. eapply H3. eapply vv. assumption.
Qed.



Lemma wf_env_extend: forall vx jj G1 R1 H1 T1,
  R_env H1 R1 G1 ->
  val_type (jj::R1) [] vx T1 nil ->
  jj vx nil -> (* redundant? *)
  vtsub jj (fun vy iy => vtp (jj::R1) [] vy T1 iy) ->
  good_bounds jj ->
  R_env (vx::H1) (jj::R1) (T1::G1).
Proof.
  intros. unfold R_env in *. destruct H as [L1 [L2 U]].
  split. simpl. rewrite L1. reflexivity.
  split. simpl. rewrite L2. reflexivity.
  intros. simpl in H. case_eq (beq_nat x (length G1)); intros E; rewrite E in H.
  - inversion H. subst T1. split. exists vx. unfold R. split.
    exists 0. intros. destruct n. omega. simpl. rewrite <-L1 in E. rewrite E. reflexivity.
    assumption. exists vx. exists jj.
    split. simpl. rewrite <-L1 in E. rewrite E. reflexivity.
    split. simpl. rewrite <-L2 in E. rewrite E. reflexivity.
    split. assumption. split. assumption. assumption.
  - destruct (U x TX H) as [[vy [EV VY]] IR]. split.
    exists vy. split.
    destruct EV as [n EV]. assert (S n > n) as N. omega. specialize (EV (S n) N). simpl in EV.
    exists n. intros. destruct n0. omega. simpl. rewrite <-L1 in E. rewrite E. assumption.
    eapply unvv. eapply valtp_extend. assumption.
    ev. exists x0. exists x1.
    split. simpl. rewrite <-L1 in E. rewrite E. assumption.
    split. simpl. rewrite <-L2 in E. rewrite E. assumption.
    split. assumption. split.
    unfold vtsub. intros. specialize (H8 vy0 iy). remember (pos iy) as p. destruct p.
    intros. eapply valtp_extend. eapply unvv. eapply H8. assumption.
    intros. eapply H8. eapply valtp_shrink. eapply unvv. eassumption.
    eapply valtp_closed in VY. eapply VY.
    assumption.
Qed.

Lemma wf_env_extend0: forall vx (jj:vset) G1 R1 H1 T1,
  R_env H1 R1 G1 ->
  jj vx nil ->
  vtsub jj (fun vy iy => vtp R1 [] vy T1 iy) ->
  good_bounds jj ->
  R_env (vx::H1) (jj::R1) (T1::G1).
Proof.
  intros.
  assert (val_type R1 [] vx T1 nil) as V0.
  specialize (H2 vx nil). simpl in H2. eapply unvv. eapply H2. assumption.
  eapply wf_env_extend. assumption. eapply unvv. eapply valtp_extend. eapply V0.
  assumption.
  unfold vtsub. intros. specialize (H2 vy iy). remember (pos iy) as p. destruct p.
  intros. eapply valtp_extend. eapply unvv. eapply H2. assumption.
  intros. eapply H2. eapply valtp_shrink. eapply unvv. eassumption.
  eapply unvv in H4. eapply valtp_closed in V0. apply V0.
  assumption.
Qed.



(* ### Inhabited types have `Good Bounds` ### *)

Definition bxor a b := match a, b with
                             | false, false => true
                             | false, true => false
                             | true, false => false
                             | true, true => true
                           end.

Lemma pos_app: forall a b,
                 pos (a ++ b) = bxor (pos a) (pos b).
Proof.
  intros. induction a; intros.
  simpl. destruct (pos b); reflexivity.
  simpl. rewrite IHa. destruct a; destruct (pos a0); destruct (pos b); reflexivity.
Qed.


(* used in invert_abs *)
Lemma valtp_bounds: forall G T1 Gv Gt,
  R_env Gv G Gt ->
  good_bounds (fun vy iy => vtp G [] vy T1 iy).
Proof.
  intros G T1 Gv Gt R. intros v iy H. eapply unvv in H. revert v iy H.
  induction T1; try rename v into v0; intros v iy H vy jy; remember (pos jy) as p; destruct p; intros HV; eapply vv; eapply unvv in HV.

  - (* TTop *)
    rewrite val_type_unfold in *. rewrite pos_app in *. simpl in *.
    destruct v; rewrite H in *; destruct vy; rewrite <-Heqp in *; inversion HV.
  - rewrite val_type_unfold in *. rewrite pos_app in *. simpl in *.
    destruct v; rewrite H in *; destruct vy; rewrite <-Heqp in *; inversion HV.

  - (* TBot *)
    rewrite val_type_unfold in *. rewrite pos_app in *. simpl in *.
    destruct v; rewrite H in *; destruct vy; rewrite <-Heqp in *; inversion HV.
  - rewrite val_type_unfold in *. rewrite pos_app in *. simpl in *.
    destruct v; rewrite H in *; destruct vy; rewrite <-Heqp in *; inversion HV.

  - (* TFun *)
    clear R IHT1_1 IHT1_2.
    assert (pos iy = true). {
      destruct iy. reflexivity.
      destruct v; rewrite val_type_unfold in *; ev; assumption.
    }
    assert (exists h1 tl1, iy ++ lb :: jy = h1 :: tl1). destruct iy. simpl. exists lb. exists jy. reflexivity. simpl. exists b. exists (iy ++ lb :: jy). reflexivity.
    assert (exists h2 tl2, iy ++ ub :: jy = h2 :: tl2). destruct iy. simpl. exists ub. exists jy. reflexivity. simpl. exists b. exists (iy ++ ub :: jy). reflexivity.
    ev. rewrite H1 in *. rewrite H2 in *.
    clear H.

    rewrite val_type_unfold in *.
    rewrite <-H2. rewrite pos_app. simpl. rewrite H0. rewrite <-Heqp. simpl.
    destruct vy; ev; repeat split; eauto; rewrite H2; unfold not; intros; inversion H6.

  - clear R IHT1_1 IHT1_2.
    assert (pos iy = true). {
      destruct iy. reflexivity.
      destruct v; rewrite val_type_unfold in *; ev; assumption.
    }
    assert (exists h1 tl1, iy ++ lb :: jy = h1 :: tl1). destruct iy. simpl. exists lb. exists jy. reflexivity. simpl. exists b. exists (iy ++ lb :: jy). reflexivity.
    assert (exists h2 tl2, iy ++ ub :: jy = h2 :: tl2). destruct iy. simpl. exists ub. exists jy. reflexivity. simpl. exists b. exists (iy ++ ub :: jy). reflexivity.
    ev. rewrite H1 in *. rewrite H2 in *.
    clear H.

    rewrite val_type_unfold in *.
    rewrite <-H1. rewrite pos_app. simpl. rewrite H0. rewrite <-Heqp. simpl.
    destruct vy; ev; repeat split; eauto; rewrite H1; unfold not; intros; inversion H6.

  - (* TSel *)
    assert ((forall (x : id) (jj : vset) (v : vl) (iy : sel),
        indexr x G = Some jj ->
        jj v iy ->
        forall (vy : vl) jy ,
        if pos jy
        then jj vy (iy ++ lb :: jy) -> jj vy (iy ++ ub :: jy)
        else jj vy (iy ++ ub :: jy) -> jj vy (iy ++ lb :: jy))) as RR.
    { unfold R_env in R. ev. intros. assert (x < length G). apply indexr_max in H3. assumption.
      rewrite H1 in H5. apply indexr_has in H5. ev. specialize (H2 _ _ H5). ev.
      rewrite H3 in H7. inversion H7. subst x2. specialize (H10 _ _ H4 vy0 jy0). assumption. }
    clear R. rename RR into R.

    rewrite val_type_unfold in *. simpl in *. destruct v0; try solve [destruct v; inversion H].
    destruct (indexr i G) eqn: In; try solve [destruct v; inversion H].
    assert (v0 v (ub::iy)). destruct v; eapply H.
    specialize (R _ _ v (ub::iy) In H0 vy jy).
    rewrite <-Heqp in R.
    destruct vy; eapply R; assumption.
  - assert ((forall (x : id) (jj : vset) (v : vl) (iy : sel),
        indexr x G = Some jj ->
        jj v iy ->
        forall (vy : vl) jy ,
        if pos jy
        then jj vy (iy ++ lb :: jy) -> jj vy (iy ++ ub :: jy)
        else jj vy (iy ++ ub :: jy) -> jj vy (iy ++ lb :: jy))) as RR.
    { unfold R_env in R. ev. intros. assert (x < length G). apply indexr_max in H3. assumption.
      rewrite H1 in H5. apply indexr_has in H5. ev. specialize (H2 _ _ H5). ev.
      rewrite H3 in H7. inversion H7. subst x2. specialize (H10 _ _ H4 vy0 jy0). assumption. }
    clear R. rename RR into R.

    rewrite val_type_unfold in *. simpl in *. destruct v0; try solve [destruct v; inversion H].
    destruct (indexr i G) eqn: In; try solve [destruct v0; inversion H].
    assert (v0 v (ub::iy)). destruct v; eapply H.
    specialize (R _ _ v (ub::iy) In H0 vy jy).
    rewrite <-Heqp in R.
    destruct vy; eapply R; assumption.
    assumption.

  - (* TMem *)
    clear R. apply unvv. destruct iy; apply vv.
    + rewrite val_type_unfold in *. destruct v. inversion H.
      simpl in *. ev. specialize (H1 vy jy). rewrite <-Heqp in H1.
      destruct vy; ev.
      split. assumption. split. assumption. eapply H1. assumption.
      split. assumption. split. assumption. eapply H1. assumption.
    + rewrite val_type_unfold in *. simpl in *.
      destruct b.
      * assert (val_type G [] v T1_2 iy). eapply unvv; destruct v; ev; eapply vv; assumption.
        assert (val_type G [] vy T1_2 (iy ++ lb :: jy) ->
                val_type G [] vy T1_2 (iy ++ ub :: jy)). {
          specialize (IHT1_2 _ _ H0 vy jy).
          rewrite <-Heqp in IHT1_2. intros. eapply unvv. eapply IHT1_2. eapply vv. assumption. }
        destruct vy; ev; split; try assumption; split; try assumption; eapply H1; assumption.
      * assert (val_type G [] v T1_1 iy). eapply unvv; destruct v; ev; eapply vv; assumption.
        assert (val_type G [] vy T1_1 (iy ++ lb :: jy) ->
              val_type G [] vy T1_1 (iy ++ ub :: jy)). {
          specialize (IHT1_1 _ _ H0 vy jy).
          rewrite <-Heqp in IHT1_1. intros. eapply unvv. eapply IHT1_1. eapply vv. assumption. }
        destruct vy; ev; split; try assumption; split; try assumption; eapply H1; assumption.

  - clear R. apply unvv. destruct iy; apply vv.
    + rewrite val_type_unfold in *. destruct v. inversion H.
      simpl in *. ev. specialize (H1 vy jy). rewrite <-Heqp in H1.
      destruct vy; ev.
      split. assumption. split. assumption. eapply H1. assumption.
      split. assumption. split. assumption. eapply H1. assumption.
    + rewrite val_type_unfold in *. simpl in *.
      destruct b.
      * assert (val_type G [] v T1_2 iy). eapply unvv; destruct v; ev; eapply vv; assumption.
        assert (val_type G [] vy T1_2 (iy ++ ub :: jy) ->
                val_type G [] vy T1_2 (iy ++ lb :: jy)). {
          specialize (IHT1_2 _ _ H0 vy jy).
          rewrite <-Heqp in IHT1_2. intros. eapply unvv. eapply IHT1_2. eapply vv. assumption. }
        destruct vy; ev; split; try assumption; split; try assumption; eapply H1; assumption.
      * assert (val_type G [] v T1_1 iy). eapply unvv; destruct v; ev; eapply vv; assumption.
        assert (val_type G [] vy T1_1 (iy ++ ub :: jy) ->
              val_type G [] vy T1_1 (iy ++ lb :: jy)). {
          specialize (IHT1_1 _ _ H0 vy jy).
          rewrite <-Heqp in IHT1_1. intros. eapply unvv. eapply IHT1_1. eapply vv. assumption. }
        destruct vy; ev; split; try assumption; split; try assumption; eapply H1; assumption.

Qed.




(* ### Inversion Lemmas ### *)

(* regular application *)
Lemma invert_abs: forall venv vf T1 T2 Gv Gt,
  R_env Gv venv Gt ->
  val_type venv [] vf (TAll T1 T2) nil ->
  exists env TX y,
    vf = (vabs env TX y) /\
    (closed 0 0 (length venv) T2 -> forall vx : vl,
       val_type venv [] vx T1 nil ->
       exists v : vl, tevaln (vx::env) y v /\ val_type venv [] v T2 nil).
Proof.
  intros ? ? ? ? ? ? R ? .
  rewrite val_type_unfold in H.
  destruct vf; try solve [inversion H].
  ev. exists l. exists t. exists t0. split. eauto.
  intros C. simpl in H1.

  intros.

  assert (exists (jj:vset),
            jj vx nil /\
            (forall vy iy, if pos iy then jj vy iy -> val_type venv0 [] vy T1 iy
                           else           val_type venv0 [] vy T1 iy -> jj vy iy) /\
            (forall vp ip, jj vp ip -> forall vy iy, if pos iy
                           then jj vy (ip ++ lb :: iy) -> jj vy (ip ++ ub :: iy)
                           else jj vy (ip ++ ub :: iy) -> jj vy (ip ++ lb :: iy))) as A. {
    exists (fun vy iy => val_type venv0 [] vy T1 iy). split.
    assumption. split.
    intros. destruct (pos iy); intros; assumption.
    intros. eapply vv in H3.
    specialize (valtp_bounds _ _ _ _ R _ _ H3). intros VB.
    specialize (VB vy iy). destruct (pos iy). intros. apply unvv. apply VB. apply vv. assumption.
    intros. apply unvv. apply VB. apply  vv. assumption. }

  ev.
  specialize (H1 vx x H3 H4 H5).
  ev.
  exists x0.
  split. eapply H1.

  eapply vtp_subst1. eapply H6. eapply C.

  ev. destruct H2. reflexivity.
Qed.

(* dependent application *)
Lemma invert_dabs: forall venv vf T1 T2 x jj,
  val_type venv [] vf (TAll T1 T2) nil ->
  indexr x venv = Some jj ->
  vtsub jj (fun vy iy => val_type venv [] vy T1 iy) ->
  good_bounds jj ->
  exists env TX y,
    vf = (vabs env TX y) /\
    forall vx : vl,
       jj vx nil ->
       exists v : vl, tevaln (vx::env) y v /\ val_type venv [] v (open (varF x) T2) nil.
Proof.
  intros.
  rewrite val_type_unfold in H.
  destruct vf; try solve [inversion H].
  ev. exists l. exists t. exists t0. split. eauto.

  intros.

  specialize (H4 vx jj H5 H1 H2).
  ev.
  exists x0.
  split. eapply H4.

  eapply vtp_subst2. simpl in *. eassumption. eassumption. eapply H0.

  ev. destruct H5. reflexivity.
Qed.

Lemma invert_var: forall (env : tenv)(x : id)(T1 : ty)(T2 : ty)
  (venv0 : list vl) (renv : list vset),
  has_type env (tvar x) T1 -> R_env venv0 renv env ->
  (exists vx jj,
              indexr x venv0 = Some vx /\
              indexr x renv = Some jj /\
              jj vx nil /\
              vtsub jj (fun vy iy => vtp renv [] vy T1 iy) /\
              good_bounds jj).
Proof. intros ? ? ? ? ? ? W2 WFE.
  unfold R_env in WFE. ev. remember (tvar x) as E.
      induction W2; inversion HeqE; try subst x0.
    + (* tvar *) destruct (H1 _ _ H2). ev. exists x0. exists x1. split. assumption. split. assumption. split. assumption.
      split. assumption. assumption.
    + (* sub *) specialize (IHW2 H3 H H0 H1). ev.
      eexists. eexists. split. eassumption. split. eassumption. split. assumption. split.
      assert (forall vy iy, if pos iy
                            then vtp renv [] vy T1 iy -> vtp renv [] vy T0 iy
                            else vtp renv [] vy T0 iy -> vtp renv [] vy T1 iy) as A.
      eapply valtp_widen_aux. eassumption. omega.
      intros. specialize (H1 _ _ H9). destruct H3. ev. exists x3. exists x4. repeat split; eassumption. reflexivity.

      intros. inversion H9. unfold vtsub.
      intros. specialize (A vy iy). specialize (H7 vy iy). destruct (pos iy).
      intros. eapply A. eapply H7. assumption.
      intros. eapply H7. eapply A. assumption.
      assumption.
Qed.


(* ### Main Theorem ### *)

(* final type safety + termination proof *)
Theorem full_total_safety : forall e tenv T,
  has_type tenv e T -> forall venv renv, R_env venv renv tenv ->
  exists v, tevaln venv e v /\ val_type renv [] v T nil.
Proof.
  intros ? ? ? W.
  induction W; intros ? ? WFE.

  - (* Case "Var". *)
    destruct (indexr_safe_ex venv0 renv env T1 x) as [v IV]. eauto. eauto.
    inversion IV as [I V].

    exists v. split. exists 0. intros. destruct n. omega. simpl. rewrite I. eauto. eapply V.

  - (* Case "Typ". *)
    repeat eexists. intros. destruct n. inversion H0. simpl. eauto.
    rewrite <-(wf_length2 venv0 renv) in H; try assumption.
    rewrite val_type_unfold. simpl. repeat split; try eapply H.
    unfold vtsub. intros. destruct (pos iy); intros; assumption.

  - (* Case "App". *)
    rewrite <-(wf_length2 _ _ _ WFE) in H.
    destruct (IHW1 venv0 renv WFE) as [vf [IW1 HVF]].
    destruct (IHW2 venv0 renv WFE) as [vx [IW2 HVX]].

    eapply invert_abs in HVF.
    destruct HVF as [venv1 [TX [y [HF IHF]]]].

    destruct (IHF H vx HVX) as [vy [IW3 HVY]].

    exists vy. split. {
      (* pick large enough n. nf+nx+ny will do. *)
      destruct IW1 as [nf IWF].
      destruct IW2 as [nx IWX].
      destruct IW3 as [ny IWY].
      exists (S (nf+nx+ny)). intros. destruct n. omega. simpl.
      rewrite IWF. subst vf. rewrite IWX. rewrite IWY. eauto.
      omega. omega. omega.
    }
    eapply HVY. eapply WFE.

  - (* Case "DApp". *)

    remember WFE as WFE'. clear HeqWFE'.
    eapply invert_var in WFE'; try eassumption. ev.

    rewrite <-(wf_length2 _ _ _ WFE) in H0.
    destruct (IHW1 venv0 renv WFE) as [vf [IW1 HVF]].
    destruct (IHW2 venv0 renv WFE) as [vx [IW2 HVX]].

    eapply invert_dabs in HVF.
    destruct HVF as [venv1 [TX [y [HF IHF]]]].

    assert (x0 = vx). { destruct IW2. assert (S x2 > x2) as SS. omega. specialize (e (S x2) SS). simpl in e.
      inversion e. rewrite H7 in H1. inversion H1. reflexivity. }
    subst x0.

    destruct (IHF vx H3) as [vy [IW3 HVY]].

    exists vy. split. {
      (* pick large enough n. nf+nx+ny will do. *)
      destruct IW1 as [nf IWF].
      destruct IW2 as [nx IWX].
      destruct IW3 as [ny IWY].
      exists (S (nf+nx+ny)). intros. destruct n. omega. simpl.
      rewrite IWF. subst vf. rewrite IWX. rewrite IWY. reflexivity.
      omega. omega. omega.
    }
    subst T. eapply HVY. eapply H2. unfold vtsub. intros. specialize (H4 vy iy). destruct (pos iy).
    intros. eapply unvv. eapply H4. assumption.
    intros. eapply H4. eapply vv. assumption.
    assumption.

  - (* Case "Abs". *)
    rewrite <-(wf_length2 _ _ _ WFE) in H.
    inversion H; subst.
    eexists. split. exists 0. intros. destruct n. omega. simpl. eauto.
    rewrite val_type_unfold. repeat split; eauto.
    intros.
    assert (R_env (vx::venv0) (jj::renv) (T1::env)) as WFE1. {
      eapply wf_env_extend0; try eassumption. unfold vtsub.
      intros. specialize (H1 vy iy). destruct (pos iy).
      intros. eapply vv. eapply H1. assumption.
      intros. eapply H1. eapply unvv. assumption. }
    specialize (IHW (vx::venv0) (jj::renv) WFE1).
    destruct IHW as [v [EV VT]]. rewrite <-(wf_length2 _ _ _ WFE) in VT.
    exists v. split. assumption.
    eapply vtp_subst3; assumption.

  - (* Case "Sub". *)
    specialize (IHW venv0 renv WFE). ev. eexists. split. eassumption.
    eapply unvv. eapply valtp_widen; eassumption.

Grab Existential Variables.
  apply 0.
Qed.
