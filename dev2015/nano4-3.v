(* Full safety for STLC *)
(* values well-typed with respect to runtime environment *)
(* inversion lemma structure *)
(* subtyping (in addition to nano2.v) *)
(* singleton types (in addtion to nano4-1.v *)

(* TODO: proper subtyping in nano4-1 and here, 
phrase singleton type lookup through stp,
dependent application *)

Require Export SfLib.

Require Export Arith.EqNat.
Require Export Arith.Le.

Module STLC.

Definition id := nat.

Inductive ty : Type :=
  | TBool  : ty           
  | TFun   : ty -> ty -> ty
  | TVar   : id -> ty
.

Inductive tm : Type :=
  | ttrue : tm
  | tfalse : tm
  | tvar : id -> tm
  | tapp : tm -> tm -> tm (* f(x) *)
  | tabs : tm -> tm (* \f x.y *)
.

Inductive vl : Type :=
| vbool : bool -> vl
| vabs  : list vl -> tm -> vl
.

Definition venv := list vl.
Definition tenv := list ty.

Hint Unfold venv.
Hint Unfold tenv.

Fixpoint length {X: Type} (l : list X): nat :=
  match l with
    | [] => 0
    | _::l' => 1 + length l'
  end.

Fixpoint index {X : Type} (n : id) (l : list X) : option X :=
  match l with
    | [] => None
    | a :: l'  => if beq_nat n (length l') then Some a else index n l'
  end.


Inductive closed: nat -> ty -> Prop :=
| cl_bool: forall k,
    closed k TBool
| cl_fun: forall k T1 T2,
    closed k T1 ->
    closed k T2 ->
    closed k (TFun T1 T2)
| cl_selb: forall k x,
    k > x ->
    closed k (TVar x)
.


Inductive has_type : tenv -> tm -> ty -> Prop :=
| t_true: forall env,
    has_type env ttrue TBool
| t_false: forall env,
    has_type env tfalse TBool
| t_varx: forall x env T1,
    index x env = Some T1 ->
    has_type env (tvar x) (TVar x)
| t_var: forall x env T1,
    index x env = Some T1 ->
    has_type env (tvar x) T1
| t_app: forall env f x T1 T2,
    has_type env f (TFun T1 T2) ->
    has_type env x T1 ->
    has_type env (tapp f x) T2
| t_abs: forall env y T1 T2,
    has_type (T1::(TFun T1 T2)::env) y T2 ->
    closed (length env) (TFun T1 T2) ->       
    has_type env (tabs y) (TFun T1 T2)
.

Inductive stp2: venv -> ty -> venv -> ty -> Prop :=
| stp2_bool: forall G1 G2,
    stp2 G1 TBool G2 TBool
| stp2_fun: forall G1 G2 T1 T2 T3 T4,
    stp2 G2 T3 G1 T1 ->
    stp2 G1 T2 G2 T4 ->
    stp2 G1 (TFun T1 T2) G2 (TFun T3 T4)
| stp2_varx: forall G1 G2 x1 x2 v,
    index x1 G1 = Some v ->
    index x2 G2 = Some v ->
    stp2 G1 (TVar x1) G2 (TVar x2)
.

Inductive wf_env : venv -> tenv -> Prop := 
| wfe_nil : wf_env nil nil
| wfe_cons : forall v t vs ts,
    val_type (v::vs) v t ->
    wf_env vs ts ->
    wf_env (cons v vs) (cons t ts)

with val_type : venv -> vl -> ty -> Prop :=
| v_bool: forall venv b TE,
    stp2 [] TBool venv TE ->
    val_type venv (vbool b) TE
| v_abs: forall env venv tenv y T1 T2 TE,
    wf_env venv tenv ->
    has_type (T1::(TFun T1 T2)::tenv) y T2 ->
    stp2 venv (TFun T1 T2) env TE -> 
    val_type env (vabs venv y) TE
| v_var: forall env venv x v TE,
    index x venv = Some v ->
    stp2 venv (TVar x) env TE -> 
    val_type env v TE
.




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
        | ttrue      => Some (Some (vbool true))
        | tfalse     => Some (Some (vbool false))
        | tvar x     => Some (index x env)
        | tabs y     => Some (Some (vabs env y))
        | tapp ef ex   =>
          match teval n env ex with
            | None => None
            | Some None => Some None
            | Some (Some vx) =>
              match teval n env ef with
                | None => None
                | Some None => Some None
                | Some (Some (vbool _)) => Some None
                | Some (Some (vabs env2 ey)) =>
                  teval n (vx::(vabs env2 ey)::env2) ey
              end
          end
      end
  end.


Hint Constructors ty.
Hint Constructors tm.
Hint Constructors vl.


Hint Constructors has_type.
Hint Constructors stp2.
Hint Constructors val_type.
Hint Constructors wf_env.

Hint Constructors option.
Hint Constructors list.

Hint Unfold index.
Hint Unfold length.

Hint Resolve ex_intro.

Lemma wf_length : forall vs ts,
                    wf_env vs ts ->
                    (length vs = length ts).
Proof.
  intros. induction H. auto.
  assert ((length (v::vs)) = 1 + length vs). constructor.
  assert ((length (t::ts)) = 1 + length ts). constructor.
  rewrite IHwf_env in H1. auto.
Qed.

Hint Immediate wf_length.

Lemma index_max : forall X vs n (T: X),
                       index n vs = Some T ->
                       n < length vs.
Proof.
  intros X vs. induction vs.
  Case "nil". intros. inversion H.
  Case "cons".
  intros. inversion H.
  case_eq (beq_nat n (length vs)); intros E.
  SCase "hit".
  rewrite E in H1. inversion H1. subst.
  eapply beq_nat_true in E. 
  unfold length. unfold length in E. rewrite E. eauto.
  SCase "miss".
  rewrite E in H1.
  assert (n < length vs). eapply IHvs. apply H1.
  compute. eauto.
Qed.

Lemma index_exists : forall X vs n,
                       n < length vs ->
                       exists (T:X), index n vs = Some T.
Proof.
  intros X vs. induction vs.
  Case "nil". intros. inversion H.
  Case "cons".
  intros. inversion H.
  SCase "hit".
  assert (beq_nat n (length vs) = true) as E. eapply beq_nat_true_iff. eauto.
  simpl. subst n. rewrite E. eauto.
  SCase "miss".
  assert (beq_nat n (length vs) = false) as E. eapply beq_nat_false_iff. omega.
  simpl. rewrite E. eapply IHvs. eauto.
Qed.


Lemma index_extend : forall X vs n a (T: X),
                       index n vs = Some T ->
                       index n (a::vs) = Some T.

Proof.
  intros.
  assert (n < length vs). eapply index_max. eauto.
  assert (n <> length vs). omega.
  assert (beq_nat n (length vs) = false) as E. eapply beq_nat_false_iff; eauto.
  unfold index. unfold index in H. rewrite H. rewrite E. reflexivity.
Qed.



Lemma stp2_extend : forall v1 G1 G2 T1 T2,
                      stp2 G1 T1 G2 T2 ->
                      stp2 (v1::G1) T1 G2 T2 /\
                      stp2 G1 T1 (v1::G2) T2 /\
                      stp2 (v1::G1) T1 (v1::G2) T2.
Proof.
  intros. induction H; repeat split; econstructor; try eapply IHstp2_1; try eapply IHstp2_2; try eapply index_extend; eauto.
Qed.

Lemma stp2_extend1 : forall v1 G1 G2 T1 T2,
                      stp2 G1 T1 G2 T2 ->
                      stp2 (v1::G1) T1 G2 T2.
Proof.
  intros. eapply stp2_extend. eauto.
Qed.

Lemma stp2_extend2 : forall v1 G1 G2 T1 T2,
                      stp2 G1 T1 G2 T2 ->
                      stp2 G1 T1 (v1::G2) T2.
Proof.
  intros. eapply stp2_extend. eauto.
Qed.

Lemma stp2_reg : forall G1 G2 T1 T2,
                      stp2 G1 T1 G2 T2 ->
                      stp2 G1 T1 G1 T1 /\
                      stp2 G2 T2 G2 T2.
Proof.
  intros. induction H; repeat split; econstructor; try eapply IHstp2_1; try eapply IHstp2_2; eauto.
Qed.

Lemma stp2_reg1 : forall G1 G2 T1 T2,
                      stp2 G1 T1 G2 T2 ->
                      stp2 G1 T1 G1 T1.
Proof.
  intros. eapply (stp2_reg G1 G2). eauto.
Qed.

Lemma stp2_reg2 : forall G1 G2 T1 T2,
                      stp2 G1 T1 G2 T2 ->
                      stp2 G2 T2 G2 T2.
Proof.
  intros. eapply (stp2_reg G1 G2). eauto.
Qed.



Lemma valtp_extend : forall vs v v1 T,
                       val_type vs v T ->
                       val_type (v1::vs) v T.
Proof.
  intros. induction H; econstructor; eauto; try eapply stp2_extend2; eauto.
Qed.


Lemma index_safe_ex: forall H1 G1 TF i,
             wf_env H1 G1 ->
             index i G1 = Some TF ->
             exists v, index i H1 = Some v /\ val_type H1 v TF.
Proof. intros. induction H.
       Case "nil". inversion H0.
       Case "cons". inversion H0.
         case_eq (beq_nat i (length ts)).
           SCase "hit".
             intros E.
             rewrite E in H3. inversion H3. subst t.
             assert (beq_nat i (length vs) = true). eauto.
             assert (index i (v :: vs) = Some v). eauto.  unfold index. rewrite H2. eauto.
             eauto.
           SCase "miss".
             intros E.
             assert (beq_nat i (length vs) = false). eauto.
             rewrite E in H3.
             assert (exists v0, index i vs = Some v0 /\ val_type vs v0 TF) as HI. eapply IHwf_env. eauto.
           inversion HI as [v0 HI1]. inversion HI1. 
           eexists. econstructor. eapply index_extend; eauto. eapply valtp_extend; eauto.
Qed.

  
Inductive res_type: venv -> option vl -> ty -> Prop :=
| not_stuck: forall venv v T,
      val_type venv v T ->
      res_type venv (Some v) T.

Hint Constructors res_type.
Hint Resolve not_stuck.


Lemma stp2_refl: forall G1 T1,
  closed (length G1) T1 ->
  stp2 G1 T1 G1 T1.
Proof.
  intros. induction T1; inversion H; eauto.
  - Case "var".
    assert (exists v, index i G1 = Some v) as E. eapply index_exists; eauto.
    destruct E.
    eapply stp2_varx; eauto.
Qed.

Lemma stp2_trans: forall G1 G2 G3 T1 T2 T3,
  stp2 G1 T1 G2 T2 ->
  stp2 G2 T2 G3 T3 ->
  stp2 G1 T1 G3 T3.
Proof.
  intros. revert H H0. revert G1 G2 G3 T1 T3.  induction T2; intros; inversion H; inversion H0.
  - Case "bool". eauto.
  - Case "fun". eauto.
  - Case "var". subst. eapply stp2_varx. eauto. rewrite <-H6. rewrite H8. eauto.
Qed.


Lemma valtp_widen: forall vf H1 H2 T1 T2,
  val_type H1 vf T1 ->
  stp2 H1 T1 H2 T2 ->
  val_type H2 vf T2.
Proof.
  intros. inversion H.
  econstructor; eauto. eapply stp2_trans; eauto.
  econstructor; eauto. eapply stp2_trans; eauto.
  econstructor; eauto. eapply stp2_trans; eauto.
Qed.


Lemma invert_abs: forall venv vf T1 T2,
  val_type venv vf (TFun T1 T2) ->
  exists env tenv y T3 T4,
    vf = (vabs env y) /\ 
    wf_env env tenv /\
    has_type (T3::(TFun T3 T4)::tenv) y T4 /\
    stp2 venv T1 env T3 /\
    stp2 env T4 venv T2.
Proof.
  intros. inversion H; try solve by inversion. inversion H2. repeat eexists; eauto. 
Qed.


(* if not a timeout, then result not stuck and well-typed *)

Theorem full_safety : forall n e tenv venv res T,
  teval n venv e = Some res -> has_type tenv e T -> wf_env venv tenv ->
  res_type venv res T.

Proof.
  intros n. induction n.
  (* 0 *)   intros. inversion H.
  (* S n *) intros. destruct e; inversion H; inversion H0.
  
  Case "True".  eapply not_stuck. eapply v_bool; eauto.
  Case "False". eapply not_stuck. eapply v_bool; eauto.

  Case "VarX".
    destruct (index_safe_ex venv0 tenv0 T1 i) as [v [I V]]; eauto. 

    rewrite I. eapply not_stuck. eapply v_var; eauto.
  
  Case "Var".
    destruct (index_safe_ex venv0 tenv0 T i) as [v [I V]]; eauto. 

    rewrite I. eapply not_stuck. eapply V.

  Case "App".
    remember (teval n venv0 e1) as tf.
    remember (teval n venv0 e2) as tx. 
    subst T.
    
    destruct tx as [rx|]; try solve by inversion.
    assert (res_type venv0 rx T1) as HRX. SCase "HRX". subst. eapply IHn; eauto.
    inversion HRX as [? vx]. 

    destruct tf as [rf|]; subst rx; try solve by inversion.  
    assert (res_type venv0 rf (TFun T1 T2)) as HRF. SCase "HRF". subst. eapply IHn; eauto.
    inversion HRF as [? vf].

    destruct (invert_abs venv0 vf T1 T2) as
        [env1 [tenv [y0 [T3 [T4 [EF [WF [HTY [STX STY]]]]]]]]]. eauto.
    (* now we know it's a closure, and we have has_type evidence *)

    assert (res_type (vx::vf::env1) res T4) as HRY.
      SCase "HRY".
        subst. eapply IHn. eauto. eauto.
        (* wf_env f x *) econstructor. eapply valtp_widen; eauto. eapply stp2_extend2; eauto. eapply stp2_extend2; eauto.
        (* wf_env f   *) econstructor. eapply v_abs; eauto. eapply stp2_extend2. eapply stp2_fun. eapply stp2_reg2; eauto. eapply stp2_reg1; eauto.
        eauto.

    inversion HRY as [? vy].

    eapply not_stuck. eapply valtp_widen; eauto. eapply stp2_extend1. eapply stp2_extend1. eauto.
    
  Case "Abs". 
    eapply not_stuck. eapply v_abs; eauto. eapply stp2_refl. rewrite (wf_length venv0 tenv0). eauto. eauto.
Qed.

End STLC.