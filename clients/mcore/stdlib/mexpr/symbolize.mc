-- Symbolization of the MExpr ast. Ignores already symbolized variables,
-- constructors, and type variables.
--
-- NOTE(aathn, 2023-05-10): Add support for symbolizing and returning the
-- free variables of an expression (similarly to eq.mc)?

include "common.mc"
include "map.mc"
include "name.mc"
include "string.mc"

include "ast.mc"
include "ast-builder.mc"
include "builtin.mc"
include "info.mc"
include "error.mc"
include "pprint.mc"
include "repr-ast.mc"

---------------------------
-- SYMBOLIZE ENVIRONMENT --
---------------------------
-- The environment differs from boot in that we use strings directly (we do
-- have SIDs available, however, if needed).

type NameEnv = {
  varEnv : Map String Name,   
  conEnv : Map String Name,   
  tyVarEnv : Map String Name, 
  tyConEnv : Map String Name, 
  reprEnv : Map String Name
}

let _nameEnvEmpty : NameEnv = {
  varEnv = mapEmpty cmpString,
  conEnv = mapEmpty cmpString,
  tyVarEnv = mapEmpty cmpString,
  tyConEnv = mapEmpty cmpString,
  reprEnv = mapEmpty cmpString
}

let mergeNameEnv = lam l. lam r. {
  varEnv = mapUnion l.varEnv r.varEnv,
  conEnv = mapUnion l.conEnv r.conEnv,
  tyVarEnv = mapUnion l.tyVarEnv r.tyVarEnv,
  tyConEnv = mapUnion l.tyConEnv r.tyConEnv,
  reprEnv = mapUnion l.reprEnv r.reprEnv
}

type SymEnv = {
  allowFree : Bool, 
  ignoreExternals : Bool,
  currentEnv : NameEnv,
  langEnv : Map String NameEnv,
  namespaceEnv : Map String Name
}

let symbolizeUpdateVarEnv = lam env : SymEnv . lam varEnv : Map String Name. 
  {env with currentEnv = {env.currentEnv with varEnv = varEnv}}

let symbolizeUpdateConEnv = lam env : SymEnv . lam conEnv : Map String Name. 
  {env with currentEnv = {env.currentEnv with conEnv = conEnv}}

let symbolizeUpdateTyVarEnv = lam env : SymEnv . lam tyVarEnv : Map String Name. 
  {env with currentEnv = {env.currentEnv with tyVarEnv = tyVarEnv}}

let symbolizeUpdateTyConEnv = lam env : SymEnv . lam tyConEnv : Map String Name. 
  {env with currentEnv = {env.currentEnv with tyConEnv = tyConEnv}}

let symbolizeUpdateReprEnv = lam env : SymEnv . lam reprEnv : Map String Name. 
  {env with currentEnv = {env.currentEnv with reprEnv = reprEnv}}

let _symEnvEmpty : SymEnv = {
  allowFree = false,
  ignoreExternals = false,
  currentEnv = _nameEnvEmpty, 
  langEnv = mapEmpty cmpString,
  namespaceEnv = mapEmpty cmpString
}

let symEnvAddBuiltinTypes : all a. SymEnv -> [(String, a)] -> SymEnv
  = lam env. lam tys. symbolizeUpdateTyConEnv env (foldl 
    (lam env. lam t. mapInsert t.0 (nameNoSym t.0) env)
    env.currentEnv.tyConEnv 
    tys)

let symEnvDefault =
  symEnvAddBuiltinTypes _symEnvEmpty builtinTypes

-- TODO(oerikss, 2023-11-14): Change all DSLs that use this name for the
-- symbolize environment to instead point to `symEnvDefault` and then
-- remove this alias and rename `_symEnvEmpty` to `symEnvEmpty`.
let symEnvEmpty = symEnvDefault



lang SymLookup
  type LookupParams = {kind : String, info : [Info], allowFree : Bool}

  sem symLookupError : LookupParams -> Name -> ()
  sem symLookupError lkup =| ident ->
    let err = (join ["Unknown ", lkup.kind, " in symbolize: ", nameGetStr ident]) in
    if deref __LSP__SOFT_ERROR then
      let errs = deref __LSP__BUFFERED_ERRORS in
      modref __LSP__BUFFERED_ERRORS (concat errs [(head lkup.info, err)]);
      ()
    else
      errorSingle lkup.info err;
      ()

  -- Get a symbol from the environment, or give an error if it is not there.
  sem getSymbol : LookupParams -> Map String Name -> Name -> Name
  sem getSymbol lkup env =| ident ->
    if nameHasSym ident then ident
    else
      optionGetOrElse
        (lam. if lkup.allowFree then ident
              else symLookupError lkup ident; ident)
        (mapLookup (nameGetStr ident) env)

  -- Insert a new symbol mapping into the environment, overriding if it exists.
  sem setSymbol : Map String Name -> Name -> (Map String Name, Name)
  sem setSymbol env =| ident -> 
    -- if nameHasSym ident then (env, ident)
    let ident = if nameHasSym ident then
      ident
    else
      nameSetNewSym ident
    in
    (mapInsert (nameGetStr ident) ident env, ident)

  -- The general case, where we may have a richer return value than simply name or env.
  sem getSymbolWith
    : all a. all b.
      { hasSym  : () -> b,
        absent  : () -> b,
        present : a  -> b }
      -> Map String a
      -> Name
      -> b
  sem getSymbolWith cases env =| ident ->
    if nameHasSym ident then cases.hasSym ()
    else
      optionMapOrElse cases.absent cases.present
        (mapLookup (nameGetStr ident) env)

  -- The general case, where we may have a richer element type than simply name.
  sem setSymbolWith
    : all a. (Name -> a)
    -> Map String a
    -> Name
    -> (Map String a, Name)
  sem setSymbolWith newElem env =| ident ->
    if nameHasSym ident then (env, ident)
    else
      let ident = nameSetNewSym ident in
      (mapInsert (nameGetStr ident) (newElem ident) env, ident)
end

-----------
-- TERMS --
-----------

lang Sym = Ast + SymLookup
  -- Symbolize with an environment
  sem symbolizeExpr : SymEnv -> Expr -> Expr
  sem symbolizeExpr (env : SymEnv) =
  | t ->
    let t = smap_Expr_Expr (symbolizeExpr env) t in
    let t = smap_Expr_Type (symbolizeType env) t in
    t

  sem symbolizeType : SymEnv -> Type -> Type
  sem symbolizeType env =
  | t -> smap_Type_Type (symbolizeType env) t

  -- Same as symbolizeExpr, but also return an env with all names bound at the
  -- top-level
  sem symbolizeTopExpr (env : SymEnv) =
  | t ->
    let t = symbolizeExpr env t in
    addTopNames env t

  sem symbolizeKind : Info -> SymEnv -> Kind -> Kind
  sem symbolizeKind info env =
  | t -> smap_Kind_Type (symbolizeType env) t

  -- TODO(vipa, 2020-09-23): env is constant throughout symbolizePat,
  -- so it would be preferrable to pass it in some other way, a reader
  -- monad or something. patEnv on the other hand changes, it would be
  -- nice to pass via state monad or something.  env is the
  -- environment from the outside, plus the names added thus far in
  -- the pattern patEnv is only the newly added names
  sem symbolizePat : all ext. SymEnv -> Map String Name -> Pat -> (Map String Name, Pat)
  sem symbolizePat env patEnv =
  | t -> smapAccumL_Pat_Pat (symbolizePat env) patEnv t

  -- Symbolize with builtin environment
  sem symbolize =
  | expr ->
    let env = symEnvDefault in
    symbolizeExpr env expr

  -- Symbolize with builtin environment and ignore errors
  sem symbolizeAllowFree =
  | expr ->
    let env = { symEnvDefault with allowFree = true } in
    symbolizeExpr env expr

  -- Add top-level identifiers (along the spine of the program) in `t`
  -- to the given environment.
  sem addTopNames (env : SymEnv) =
  | t -> env
end

lang VarSym = Sym + VarAst
  sem symbolizeExpr (env : SymEnv) =
  | TmVar t ->
    let ident =
      getSymbol {kind = "variable",
                 info = [t.info],
                 allowFree = env.allowFree}
        env.currentEnv.varEnv t.ident
    in
    TmVar {t with ident = ident}
end

lang LamSym = Sym + LamAst + VarSym
  sem symbolizeExpr (env : SymEnv) =
  | TmLam t ->
    match setSymbol env.currentEnv.varEnv t.ident with (varEnv, ident) in
    TmLam {t with ident = ident,
                  tyAnnot = symbolizeType env t.tyAnnot,
                  body = symbolizeExpr (symbolizeUpdateVarEnv env varEnv) t.body}
end

lang LetSym = Sym + LetAst + AllTypeAst
  sem symbolizeExpr (env : SymEnv) =
  | TmLet t ->
    match symbolizeTyAnnot env t.tyAnnot with (tyVarEnv, tyAnnot) in
    match setSymbol env.currentEnv.varEnv t.ident with (varEnv, ident) in
    TmLet {t with ident = ident,
                  tyAnnot = tyAnnot,
                  body = symbolizeExpr (symbolizeUpdateTyVarEnv env tyVarEnv) t.body,
                  inexpr = symbolizeExpr (symbolizeUpdateVarEnv env varEnv) t.inexpr}

  sem symbolizeTyAnnot : SymEnv -> Type -> (Map String Name, Type)
  sem symbolizeTyAnnot env =
  | tyAnnot ->
    let symbolized = symbolizeType env tyAnnot in
    match stripTyAll symbolized with (vars, stripped) in
    (foldl (lam env. lam nk. mapInsert (nameGetStr nk.0) nk.0 env)
       env.currentEnv.tyVarEnv vars, symbolized)

  sem addTopNames (env : SymEnv) =
  | TmLet t ->
    let varEnv = mapInsert (nameGetStr t.ident) t.ident env.currentEnv.varEnv in
    addTopNames (symbolizeUpdateVarEnv env varEnv) t.inexpr
end

lang RecLetsSym = Sym + RecLetsAst + LetSym
  sem symbolizeExpr (env : SymEnv) =
  | TmRecLets t ->
    -- Generate fresh symbols for all identifiers and add to the environment
    let setSymbolIdent = lam env. lam b.
      match setSymbol env b.ident with (env, ident) in
      (env, {b with ident = ident})
    in
    match mapAccumL setSymbolIdent env.currentEnv.varEnv t.bindings with (varEnv, bindings) in
    let newEnv = symbolizeUpdateVarEnv env varEnv in

    -- Symbolize all bodies with the new environment
    let bindings =
      map (lam b. match symbolizeTyAnnot env b.tyAnnot with (tyVarEnv, tyAnnot) in
                  {b with body = symbolizeExpr (symbolizeUpdateTyVarEnv newEnv tyVarEnv) b.body,
                          tyAnnot = tyAnnot})
        bindings in

    TmRecLets {t with bindings = bindings,
                      inexpr = symbolizeExpr newEnv t.inexpr}

  sem addTopNames (env : SymEnv) =
  | TmRecLets t ->
    let varEnv =
      foldr (lam b. mapInsert (nameGetStr b.ident) b.ident) env.currentEnv.varEnv t.bindings in
    addTopNames (symbolizeUpdateVarEnv env varEnv) t.inexpr
end

lang ExtSym = Sym + ExtAst
  sem symbolizeExpr (env : SymEnv) =
  | TmExt t ->
    let setName = if env.ignoreExternals then lam x. lam y. (x, y) else setSymbol in
    match setName env.currentEnv.varEnv t.ident with (varEnv, ident) in
    TmExt {t with ident = ident,
                  inexpr = symbolizeExpr (symbolizeUpdateVarEnv env varEnv) t.inexpr,
                  tyIdent = symbolizeType env t.tyIdent}

  sem addTopNames (env : SymEnv) =
  | TmExt t ->
    let varEnv = mapInsert (nameGetStr t.ident) t.ident env.currentEnv.varEnv in
    addTopNames (symbolizeUpdateVarEnv env varEnv) t.inexpr
end

lang TypeSym = Sym + TypeAst
  sem symbolizeExpr (env : SymEnv) =
  | TmType t ->
    match setSymbol env.currentEnv.tyConEnv t.ident with (tyConEnv, ident) in
    match mapAccumL setSymbol env.currentEnv.tyVarEnv t.params with (tyVarEnv, params) in
    TmType {t with ident = ident,
                   params = params,
                   tyIdent = symbolizeType (symbolizeUpdateTyVarEnv env tyVarEnv) t.tyIdent,
                   inexpr = symbolizeExpr (symbolizeUpdateTyConEnv env tyConEnv) t.inexpr}

  sem addTopNames (env : SymEnv) =
  | TmType t ->
    let tyConEnv = mapInsert (nameGetStr t.ident) t.ident env.currentEnv.tyConEnv in
    addTopNames (symbolizeUpdateTyConEnv env tyConEnv) t.inexpr
end

lang DataSym = Sym + DataAst
  sem symbolizeExpr (env : SymEnv) =
  | TmConDef t ->
    match setSymbol env.currentEnv.conEnv t.ident with (conEnv, ident) in
    TmConDef {t with ident = ident,
                     tyIdent = symbolizeType env t.tyIdent,
                     inexpr = symbolizeExpr (symbolizeUpdateConEnv env conEnv) t.inexpr}
  | TmConApp t ->
    let ident =
      getSymbol {kind = "constructor",
                 info = [t.info],
                 allowFree = env.allowFree}
        env.currentEnv.conEnv t.ident
    in
    TmConApp {t with ident = ident,
                     body = symbolizeExpr env t.body}

  sem addTopNames (env : SymEnv) =
  | TmConDef t ->
    let conEnv = mapInsert (nameGetStr t.ident) t.ident env.currentEnv.conEnv in
    addTopNames (symbolizeUpdateConEnv env conEnv) t.inexpr
end

lang MatchSym = Sym + MatchAst
  sem symbolizeExpr (env : SymEnv) =
  | TmMatch t ->
    match symbolizePat env (mapEmpty cmpString) t.pat with (thnVarEnv, pat) in
    let thnPatEnv = symbolizeUpdateVarEnv env (mapUnion env.currentEnv.varEnv thnVarEnv) in
    TmMatch {t with target = symbolizeExpr env t.target,
                    pat = pat,
                    thn = symbolizeExpr thnPatEnv t.thn,
                    els = symbolizeExpr env t.els}
end

lang OpImplSym = OpImplAst + Sym + LetSym
  sem symbolizeExpr env =
  | TmOpImpl x ->
    let ident = getSymbol
      { kind = "variable"
      , info = [x.info]
      , allowFree = env.allowFree
      }
      env.currentEnv.varEnv
      x.ident in
    match symbolizeTyAnnot env x.specType with (tyVarEnv, specType) in
    let body = symbolizeExpr (symbolizeUpdateTyVarEnv env tyVarEnv) x.body in
    let inexpr = symbolizeExpr env x.inexpr in
    TmOpImpl {x with ident = ident, body = body, specType = specType, inexpr = inexpr}
end

lang OpDeclSym = OpDeclAst + Sym + OpImplAst + ReprDeclAst + OpImplSym
  sem symbolizeExpr env =
  | TmOpDecl x ->
    let symbolizeReprDecl = lam reprEnv. lam binding.
      match mapAccumL setSymbol env.currentEnv.tyVarEnv binding.1 .vars with (tyVarEnv, vars) in
      let newEnv = (symbolizeUpdateTyVarEnv env tyVarEnv) in
      match setSymbol reprEnv binding.0 with (reprEnv, ident) in
      let res =
        { ident = ident
        , vars = vars
        , pat = symbolizeType newEnv binding.1 .pat
        , repr = symbolizeType newEnv binding.1 .repr
        }
      in (reprEnv, res) in

    match setSymbol env.currentEnv.varEnv x.ident with (varEnv, ident) in
    let newEnv = symbolizeUpdateVarEnv env varEnv in
    let inexpr = symbolizeExpr newEnv x.inexpr in
    TmOpDecl
      { x with ident = ident
      , tyAnnot = symbolizeType env x.tyAnnot
      , inexpr = inexpr
      , ty = symbolizeType env x.ty
      }
end

lang ReprTypeSym = Sym + ReprDeclAst
  sem symbolizeExpr env =
  | TmReprDecl x ->
    match setSymbol env.currentEnv.reprEnv x.ident with (reprEnv, ident) in
    match mapAccumL setSymbol env.currentEnv.tyVarEnv x.vars with (tyVarEnv, vars) in
    let rhsEnv = (symbolizeUpdateTyVarEnv env tyVarEnv) in
    let pat = symbolizeType rhsEnv x.pat in
    let repr = symbolizeType rhsEnv x.repr in
    let inexpr = symbolizeExpr (symbolizeUpdateReprEnv env reprEnv) x.inexpr in
    TmReprDecl {x with ident = ident, pat = pat, repr = repr, vars = vars, inexpr = inexpr}
end

lang OpVarSym = OpVarAst + Sym
  sem symbolizeExpr env =
  | TmOpVar x ->
    let ident = getSymbol
      { kind = "variable"
      , info = [x.info]
      , allowFree = env.allowFree
      }
      env.currentEnv.varEnv
      x.ident in
    TmOpVar {x with ident = ident}
end

-----------
-- TYPES --
-----------

lang VariantTypeSym = Sym + VariantTypeAst
  sem symbolizeType env =
  | TyVariant t & ty ->
    if eqi (mapLength t.constrs) 0 then ty
    else errorSingle [t.info] "Symbolizing non-empty variant types not yet supported"
end

lang ConTypeSym = Sym + ConTypeAst
  sem symbolizeType env =
  | TyCon t ->
    let ident =
      getSymbol {kind = "type constructor",
                 info = [t.info],
                 allowFree = env.allowFree}
        env.currentEnv.tyConEnv t.ident
    in
    TyCon {t with ident = ident, data = symbolizeType env t.data}
end

lang DataTypeSym = Sym + DataTypeAst
  sem symbolizeType env =
  | TyData t ->
    let cons =
      setFold (lam ks. lam k.
        setInsert
          (getSymbol {kind = "constructor",
                      info = [t.info],
                      allowFree = env.allowFree}
             env.currentEnv.conEnv k) ks)
        (setEmpty nameCmp) t.cons
    in TyData {t with cons = cons}
end

lang VarTypeSym = Sym + VarTypeAst + UnknownTypeAst
  sem symbolizeType env =
  | TyVar t ->
    let ident =
      getSymbol {kind = "type variable",
                 info = [t.info],
                 allowFree = env.allowFree}
        env.currentEnv.tyVarEnv t.ident
    in
    TyVar {t with ident = ident}
end

lang AllTypeSym = Sym + AllTypeAst
  sem symbolizeType env =
  | TyAll t ->
    let kind = symbolizeKind t.info env t.kind in
    match setSymbol env.currentEnv.tyVarEnv t.ident with (tyVarEnv, ident) in
    TyAll {t with ident = ident,
                  ty = symbolizeType (symbolizeUpdateTyVarEnv env tyVarEnv) t.ty,
                  kind = kind}
end

lang DataKindSym = Sym + DataKindAst
  sem symbolizeKind info env =
  | Data t ->
    let symbolizeCons = lam cons.
      setFold
        (lam ks. lam k.
          setInsert
            (getSymbol {kind = "constructor",
                        info = [info],
                        allowFree = env.allowFree}
               env.currentEnv.conEnv k) ks)
        (setEmpty nameCmp)
        cons
    in
    let types =
      foldl
        (lam m. lam b.
          match b with (t, r) in
          let t = getSymbol {kind = "type constructor",
                             info = [info],
                             allowFree = env.allowFree}
                    env.currentEnv.tyConEnv t
          in
          mapInsert t {r with lower = symbolizeCons r.lower,
                              upper = optionMap symbolizeCons r.upper} m)
        (mapEmpty nameCmp)
        (mapBindings t.types)
    in
    Data {t with types = types}
end

lang ReprSubstSym = Sym + ReprSubstAst
  sem symbolizeType env =
  | TySubst x ->
    let arg = symbolizeType env x.arg in
    let subst = getSymbol
      { kind = "repr"
      , info = [x.info]
      , allowFree = env.allowFree
      }
      env.currentEnv.reprEnv
      x.subst in
    TySubst {x with arg = arg, subst = subst}
end

--------------
-- PATTERNS --
--------------

let _symbolizePatName: Map String Name -> PatName -> (Map String Name, PatName) =
  use SymLookup in
  lam patEnv. lam pname.
    match pname with PName name then
      getSymbolWith
        { hasSym = lam. (patEnv, PName name),
          absent = lam.
            let name = nameSetNewSym name in
            (mapInsert (nameGetStr name) name patEnv, PName name),
          present = lam name. (patEnv, PName name)
        } patEnv name
    else (patEnv, pname)

lang NamedPatSym = Sym + NamedPat
  sem symbolizePat env patEnv =
  | PatNamed p ->
    match _symbolizePatName patEnv p.ident with (patEnv, patname) in
    (patEnv, PatNamed {p with ident = patname})
end

lang SeqEdgePatSym = Sym + SeqEdgePat
  sem symbolizePat env patEnv =
  | PatSeqEdge p ->
    match mapAccumL (symbolizePat env) patEnv p.prefix with (patEnv, prefix) in
    match _symbolizePatName patEnv p.middle with (patEnv, middle) in
    match mapAccumL (symbolizePat env) patEnv p.postfix with (patEnv, postfix) in
    (patEnv, PatSeqEdge {p with prefix = prefix,
                                middle = middle,
                                postfix = postfix})
end

lang DataPatSym = Sym + DataPat
  sem symbolizePat env patEnv =
  | PatCon r ->
    let ident =
      getSymbol {kind = "constructor",
                 info = [r.info],
                 allowFree = env.allowFree}
        env.currentEnv.conEnv r.ident
    in
    match symbolizePat env patEnv r.subpat with (patEnv, subpat) in
    (patEnv, PatCon {r with ident = ident,
                            subpat = subpat})
end

lang NotPatSym = Sym + NotPat
  sem symbolizePat env patEnv =
  | PatNot p ->
    -- NOTE(vipa, 2020-09-23): new names in a not-pattern do not
    -- matter since they will never bind (it should probably be an
    -- error to bind a name inside a not-pattern, but we're not doing
    -- that kind of static checks yet.  Note that we still need to run
    -- symbolizePat though, constructors must refer to the right symbol.
    match symbolizePat env patEnv p.subpat with (_, subpat) in
    (patEnv, PatNot {p with subpat = subpat})
end

------------------------------
-- MEXPR SYMBOLIZE FRAGMENT --
------------------------------

lang MExprSym =

  -- Default implementations (Terms)
  RecordAst + ConstAst + UtestAst + SeqAst + NeverAst + AppAst +

  -- Default implementations (Types)
  UnknownTypeAst + BoolTypeAst + IntTypeAst + FloatTypeAst + CharTypeAst +
  FunTypeAst + SeqTypeAst + TensorTypeAst + RecordTypeAst + AppTypeAst +

  -- Default implementations (Kinds)
  PolyKindAst + MonoKindAst + RecordKindAst +

  -- Default implementations (Patterns)
  SeqTotPat + RecordPat + IntPat + CharPat + BoolPat + AndPat + OrPat +

  -- Non-default implementations (Terms)
  VarSym + LamSym + LetSym + ExtSym + TypeSym + RecLetsSym + DataSym +
  MatchSym +

  -- Non-default implementations (Types)
  VariantTypeSym + ConTypeSym + DataTypeSym + VarTypeSym + AllTypeSym +

  -- Non-default implementations (Kinds)
  DataKindSym +

  -- Non-default implementations (Patterns)
  NamedPatSym + SeqEdgePatSym + DataPatSym + NotPatSym
end

lang RepTypesSym = OpDeclSym + OpImplSym + OpVarSym + ReprSubstSym + ReprTypeSym
end

-----------
-- TESTS --
-----------

let _and = lam cond. lam f. lam. if cond () then f () else false
let _andFold = lam f. lam acc. lam e. _and acc (f e)

-- To test that the symbolization works as expected, we define functions that
-- verify all names in the AST have been symbolized.
lang SymCheck = MExprSym
  sem isFullySymbolized : Expr -> Bool
  sem isFullySymbolized =
  | ast -> isFullySymbolizedExpr ast ()

  sem isFullySymbolizedExpr : Expr -> () -> Bool
  sem isFullySymbolizedExpr =
  | TmVar t -> lam. nameHasSym t.ident
  | TmLam t ->
    _and (lam. nameHasSym t.ident)
      (_and
         (isFullySymbolizedType t.tyAnnot)
         (isFullySymbolizedExpr t.body))
  | TmLet t ->
    _and (lam. nameHasSym t.ident)
      (_and (isFullySymbolizedType t.tyAnnot)
         (_and
            (isFullySymbolizedExpr t.body)
            (isFullySymbolizedExpr t.inexpr)))
  | TmRecLets t ->
    let isFullySymbolizedBinding = lam b.
      _and (lam. nameHasSym b.ident)
        (_and
           (isFullySymbolizedType b.tyAnnot)
           (isFullySymbolizedExpr b.body))
    in
    _and
      (foldl (_andFold isFullySymbolizedBinding) (lam. true) t.bindings)
      (isFullySymbolizedExpr t.inexpr)
  | TmType t ->
    _and (lam. forAll nameHasSym t.params)
      (_and
         (isFullySymbolizedType t.tyIdent)
         (isFullySymbolizedExpr t.inexpr))
  | TmConDef t ->
    _and (lam. nameHasSym t.ident)
      (_and
         (isFullySymbolizedType t.tyIdent)
         (isFullySymbolizedExpr t.inexpr))
  | TmConApp t ->
    _and (lam. nameHasSym t.ident) (isFullySymbolizedExpr t.body)
  | TmExt t ->
    _and (lam. nameHasSym t.ident)
      (_and
         (isFullySymbolizedType t.tyIdent)
         (isFullySymbolizedExpr t.inexpr))
  | t ->
    _and (sfold_Expr_Expr (_andFold isFullySymbolizedExpr) (lam. true) t)
      (_and
         (sfold_Expr_Type (_andFold isFullySymbolizedType) (lam. true) t)
         (sfold_Expr_Pat (_andFold isFullySymbolizedPat) (lam. true) t))

  sem isFullySymbolizedPat : Pat -> () -> Bool
  sem isFullySymbolizedPat =
  | PatNamed {ident = PName id} -> lam. nameHasSym id
  | PatCon t ->
    _and (lam. nameHasSym t.ident) (isFullySymbolizedPat t.subpat)
  | p ->
    _and
      (sfold_Pat_Pat (_andFold isFullySymbolizedPat) (lam. true) p)
      (sfold_Pat_Type (_andFold isFullySymbolizedType) (lam. true) p)

  sem isFullySymbolizedType : Type -> () -> Bool
  sem isFullySymbolizedType =
  | TyCon {ident = ident} | TyVar {ident = ident} -> lam. nameHasSym ident
  | TyAll t ->
    _and (lam. nameHasSym t.ident) (isFullySymbolizedType t.ty)
  | ty ->
    sfold_Type_Type (_andFold isFullySymbolizedType) (lam. true) ty
end

lang TestLang = SymCheck + MExprPrettyPrint
end

mexpr

use TestLang in

let x = nameSym "x" in
utest isFullySymbolized (ulam_ "x" (var_ "x")) with false in
utest isFullySymbolized (nulam_ x (var_ "x")) with false in
utest isFullySymbolized (nulam_ x (nvar_ x)) with true in

let testSymbolize = lam ast. lam testEqStr.
  let symbolizeCalls =
    [ symbolize
    , symbolizeExpr {symEnvDefault with allowFree = true}] in
  foldl
    (lam acc. lam symb.
      if acc then
        let symAst = symb ast in
        isFullySymbolized symAst
      else false)
    true symbolizeCalls
in

let base = (ulam_ "x" (ulam_ "y" (app_ (var_ "x") (var_ "y")))) in
utest testSymbolize base false with true in

let rec = urecord_ [("k1", base), ("k2", (int_ 1)), ("k3", (int_ 2))] in
utest testSymbolize rec false with true in

let letin = bind_ (ulet_ "x" rec) (app_ (var_ "x") base) in
utest testSymbolize letin false with true in

let lettypein = bindall_ [
  type_ "Type" [] tystr_,
  type_ "Type" [] (tycon_ "Type"),
  lam_ "Type" (tycon_ "Type") (var_ "Type")
] in
utest testSymbolize lettypein false with true in

let rlets =
  bind_ (ureclets_ [("x", (var_ "y")), ("y", (var_ "x"))])
    (app_ (var_ "x") (var_ "y")) in
utest testSymbolize rlets false with true in

let const = int_ 1 in
utest testSymbolize const false with true in

let data = bind_ (ucondef_ "Test") (conapp_ "Test" base) in
utest testSymbolize data false with true in

let varpat = match_ uunit_ (pvar_ "x") (var_ "x") base in
utest testSymbolize varpat false with true in

let recpat =
  match_ base
    (prec_ [("k1", (pvar_ "x")), ("k2", pvarw_), ("k3", (pvar_ "x"))])
    (var_ "x") uunit_ in
utest testSymbolize recpat false with true in

let datapat =
  bind_ (ucondef_ "Test")
    (match_ uunit_ (pcon_ "Test" (pvar_ "x")) (var_ "x") uunit_) in
utest testSymbolize datapat false with true in

let litpat =
  match_ uunit_ (pint_ 1)
    (match_ uunit_ (pchar_ 'c')
       (match_ uunit_ (ptrue_)
            base
          uunit_)
       uunit_)
    uunit_ in
utest testSymbolize litpat false with true in

let ut = utest_ base base base in
utest testSymbolize ut false with true in

let utu = utestu_ base base base (uconst_ (CEqi{})) in
utest testSymbolize utu false with true in

let seq = seq_ [base, data, const, utu] in
utest testSymbolize seq false with true in

let nev = never_ in
utest testSymbolize nev false with true in

let matchand = bind_ (ulet_ "a" (int_ 2)) (match_ (int_ 1) (pand_ (pint_ 1) (pvar_ "a")) (var_ "a") (never_)) in
utest testSymbolize matchand false with true in

let matchor = bind_ (ulet_ "a" (int_ 2)) (match_ (int_ 1) (por_ (pvar_ "a") (pvar_ "a")) (var_ "a") (never_)) in
utest testSymbolize matchor false with true in

-- NOTE(vipa, 2020-09-23): (var_ "a") should refer to the "a" from ulet_, not the pattern, that's intended, in case someone happens to notice and finds it odd
let matchnot = bind_ (ulet_ "a" (int_ 2)) (match_ (int_ 1) (pnot_ (pvar_ "a")) (var_ "a") (never_)) in
utest testSymbolize matchnot false with true in

let matchoredge = bind_ (ulet_ "a" (int_ 2)) (match_ (int_ 1) (por_ (pseqedge_ [pchar_ 'a'] "a" []) (pseqedge_ [pchar_ 'b'] "a" [])) (var_ "a") (never_)) in
utest testSymbolize matchoredge false with true in

let lettyvar = let_ "f" (tyall_ "a" (tyarrow_ (tyvar_ "a") (tyvar_ "a")))
                        (lam_ "x" (tyvar_ "a") (var_ "x")) in
utest testSymbolize lettyvar false with true in

-- NOTE(larshum, 2023-01-20): This test checks that the type parameters of a
-- type application are not erased when the constructor is a free variable.
let tyconApps = bindall_ [
  let_ "f"
    (tyall_ "a" (tyarrow_ (tyapp_ (tycon_ "Con") (tyvar_ "a")) (tyvar_ "a")))
    (ulam_ "x" never_)
] in
utest expr2str (symbolizeAllowFree tyconApps) with expr2str tyconApps using eqString in

()
