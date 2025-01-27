include "javascript/compile.mc"
include "javascript/mcore.mc"
include "mexpr/phase-stats.mc"
include "mexpr/profiling.mc"
include "mexpr/remove-ascription.mc"
include "mexpr/runtime-check.mc"
include "mexpr/shallow-patterns.mc"
include "mexpr/symbolize.mc"
include "mexpr/type-check.mc"
include "mexpr/utest-generate.mc"
include "mexpr/constant-fold.mc"
include "pmexpr/demote.mc"
include "jvm/compile.mc"
include "mlang/main.mc"
include "peval/compile.mc"

include "./root.mc"

lang MCoreCompile =
  BootParser +
  PMExprDemote +
  MExprCmp +
  MExprSym + MExprRemoveTypeAscription + MExprTypeCheck +
  MExprUtestGenerate + MExprRuntimeCheck + MExprProfileInstrument +
  MExprPrettyPrint +
  MExprLowerNestedPatterns +
  MExprConstantFold +
  SpecializeCompile +
  PprintTyAnnot + HtmlAnnotator
end

lang MLangMExprTypeChecker = MLangRoot
  type TypeCheckedMExprLSP = {
    expr: Expr,
    warnings: [Diagnostic],
    errors: [Diagnostic]
  }

  sem lsTypeCheckMExpr : Expr -> TypeCheckedMExprLSP
  sem lsTypeCheckMExpr =| expr ->
    -- Ugly hacking to not make typeCheckExpr
    -- crash in the MLang pipeline
    modref __LSP__SOFT_ERROR true;
    modref __LSP__BUFFERED_ERRORS [];
    modref __LSP__BUFFERED_WARNINGS [];

    let expr = use MCoreCompile in typeCheckExpr {
      typcheckEnvDefault with
      disableConstructorTypes = false
    } expr in

    let errors = deref __LSP__BUFFERED_ERRORS in
    let warnings = deref __LSP__BUFFERED_WARNINGS in

    modref __LSP__SOFT_ERROR false;
    modref __LSP__BUFFERED_ERRORS [];
    modref __LSP__BUFFERED_WARNINGS [];

    {
      expr = expr,
      warnings = warnings,
      errors = errors
    }
end

lang MLangMExprCompiler = MLangRoot
	sem lsCompileMLangToMExpr : Path -> MLangFile -> MLangFile
	sem lsCompileMLangToMExpr filename =
  | file & CSymbolized (symbolized & { program = program }) ->
    eprintln (join ["Mexprering file"]);

    match result.consume (checkComposition program) with (warnings, res) in 
    switch res 
      case Left errs then 
        iter raiseError errs ;
        never
      case Right env then
        let ctx = _emptyCompilationContext env in 
        let res = result.consume (compile ctx program) in 
        match res with (_, rhs) in 
        match rhs with Right expr in

        let expr = postprocess env.semSymMap expr in 
        match use MLangMExprTypeChecker in lsTypeCheckMExpr expr with {
          expr = expr,
          warnings = warnings,
          errors = errors
        } in

        CTypeChecked {
          symbolized = symbolized,
          expr = expr,
          diagnostics = join [
            map (addSeverity (Error ())) errors,
            map (addSeverity (Warning ())) warnings
          ]
        }
    end
end