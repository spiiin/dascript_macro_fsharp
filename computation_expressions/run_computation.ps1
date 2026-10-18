param([string]$Daslang = $env:DASLANG_EXE, [switch]$Test)
. (Join-Path $PSScriptRoot 'source_paths.ps1')
$ErrorActionPreference = 'Stop'
if (-not $Daslang) {
    $command = Get-Command daslang.exe -ErrorAction SilentlyContinue
    if ($command) { $Daslang = $command.Source }
    elseif (Test-Path -LiteralPath 'C:\src\daslang-0.6.5-RC2\sdk\daslang_bundle\bin\daslang.exe') {
        $Daslang = 'C:\src\daslang-0.6.5-RC2\sdk\daslang_bundle\bin\daslang.exe'
    } else { throw 'Specify -Daslang or DASLANG_EXE.' }
}
$Daslang = (Resolve-Path -LiteralPath $Daslang).Path
function Check([string]$File, [bool]$Pass, [string]$Expected) {
    $lines = & $Daslang $File -no-module-cache 2>&1
    $code = $LASTEXITCODE
    $lines | ForEach-Object { Write-Host $_ }
    if (($code -eq 0) -ne $Pass -or ($lines -join "`n") -notmatch [regex]::Escape($Expected)) {
        throw "Unexpected result for $File (exit $code)."
    }
}
Push-Location $PSScriptRoot
try {
    Check 'examples/task_events_demo.das' $true 'Task event demo OK'
    Check 'examples/task_array_demo.das' $true 'Task array demo OK'
    Check 'examples/task_and_bind_demo.das' $true 'Task and_bind demo OK'
    Check 'examples/task_extended_demo.das' $true 'Task extended demo OK'
    Check 'examples/task_delay_demo.das' $true 'Task delay demo OK'
    Check 'examples/task_cancellation_demo.das' $true 'Task cancellation demo OK'
    Check 'examples/task_timeout_demo.das' $true 'Task timeout demo OK'
    Check 'examples/task_scheduler_demo.das' $true 'Task scheduler demo OK'
    Check 'examples/task_combinators_demo.das' $true 'Task composition demo OK'
    Check 'examples/task_async_demo.das' $true 'Task async demo OK'
    Check 'examples/task_async_resources_demo.das' $true 'Task async resources demo OK'
    Check 'examples/task_demo.das' $true 'Task demo OK'
    Check 'examples/task_external_demo.das' $true 'External task demo OK'
    Check 'examples/move_resources_demo.das' $true 'move-only resources demo OK'
    Check 'examples/sequence_next_move_demo.das' $true 'sequence_next_move demo OK'
    Check 'examples/deferred_move_collections_demo.das' $true 'deferred move-only collections demo OK'
    Check 'examples/move_collections_demo.das' $true 'move-only collections demo OK'
    Check 'examples/move_ce_demo.das' $true 'move-only CE demo OK'
    Check 'examples/state_operations_demo.das' $true 'State operations demo OK'
    Check 'examples/computation_demo.das' $true 'computation demo OK'
    Check 'examples/computation_control_demo.das' $true 'control flow demo OK'
    Check 'examples/state_demo.das' $true 'state demo OK'
    Check 'examples/writer_demo.das' $true 'writer demo OK'
    Check 'examples/writer_result_demo.das' $true 'writer/result demo OK'
    Check 'examples/state_writer_result_demo.das' $true 'state/writer/result demo OK'
    Check 'examples/state_result_demo.das' $true 'state/result demo OK'
    Check 'examples/resources_demo.das' $true 'resources demo OK'
    Check 'examples/list_demo.das' $true 'list demo OK'
    Check 'examples/coroutine_scope_demo.das' $true 'coroutine scope demo OK'
    Check 'examples/coroutine_slots_demo.das' $true 'coroutine slots demo OK'
    Check 'examples/coroutine_scheduler_demo.das' $true 'coroutine scheduler demo OK'
    Check 'examples/coroutine_demo.das' $true 'coroutine demo OK'
    Check 'examples/sequence_demo.das' $true 'sequence demo OK'
    Check 'examples/sequence_resources_demo.das' $true 'sequence resources demo OK'
    Check 'examples/sequence_shared_demo.das' $true 'sequence shared capture demo OK'
    Check 'examples/try_with_demo.das' $true 'try_with demo OK'
    Check 'examples/reader_result_demo.das' $true 'reader/result demo OK'
    Check 'examples/reader_demo.das' $true 'reader demo OK'
    Check 'examples/validation_demo.das' $true 'validation demo OK'
    Check 'examples/and_bind_demo.das' $true 'and_bind demo OK'
    Check 'examples/bind_return_demo.das' $true 'bind_return demo OK'
    Check 'examples/effect_bind_return_demo.das' $true 'effect bind_return demo OK'
    Check 'examples/bind2_return_demo.das' $true 'bind2_return demo OK'
    Check 'examples/bind2_demo.das' $true 'bind2 demo OK'
    Check 'examples/run_demo.das' $true 'run demo OK'
    Check 'examples/deferred_demo.das' $true 'deferred demo OK'
    Check 'examples/deferred_sequence_demo.das' $true 'deferred sequence demo OK'
    Check 'examples/loop_protocol_demo.das' $true 'loop protocol demo OK'
    Check 'examples/zip_for_demo.das' $true 'zip for demo OK'
    Check 'examples/source_demo.das' $true 'source protocol demo OK'
    Check 'examples/sequence_nested_cleanup_demo.das' $true 'nested Sequence cleanup demo OK'
    Check 'examples/fallback_cleanup_demo.das' $true 'fallback cleanup demo OK'
    Check 'examples/single_cleanup_demo.das' $true 'single For cleanup demo OK'
    Check 'examples/zip_cleanup_demo.das' $true 'zip cleanup demo OK'
    if ($Test) {
        Check 'tests/test_task_array.das' $true 'Task array checks OK'
        Check 'tests/test_task_array_lifetime.das' $true 'Task array lifetime checks OK'
        & (Join-Path $PSScriptRoot 'test_task_keyboard.ps1') -Daslang $Daslang
        & (Join-Path $PSScriptRoot 'test_task_glfw_keyboard.ps1') -Daslang $Daslang
        Check 'tests/test_task_events.das' $true 'Task event checks OK'
        Check 'tests/test_task_events_pointer.das' $false 'payload must own its data'
        Check 'tests/test_task_events_move_payload.das' $false 'broadcast payload must be copyable'
        Check 'tests/test_task_delay.das' $true 'Task delay checks OK'
        Check 'tests/test_task_delay_lifetime.das' $true 'Task delay lifetime checks OK'
        Check 'tests/test_task_cancellation.das' $true 'Task cancellation checks OK'
        Check 'tests/test_task_cancellation_lifetime.das' $true 'Task cancellation lifetime checks OK'
        Check 'tests/test_task_timeouts.das' $true 'Task timeout checks OK'
        Check 'tests/test_task_timeout_lifetime.das' $true 'Task timeout lifetime checks OK'
        Check 'tests/test_task_scheduler.das' $true 'Task scheduler checks OK'
        Check 'tests/test_task_scheduler_safety.das' $true 'Task scheduler safety checks OK'
        Check 'tests/test_task_scheduler_lifetime.das' $true 'Task scheduler lifetime checks OK'
        Check 'tests/test_task_scheduler_type.das' $false 'can only move compatible type'
        Check 'tests/test_task_combinators.das' $true 'Task composition checks OK'
        Check 'tests/test_task_combinators_lifetime.das' $true 'Task composition lifetime checks OK'
        Check 'tests/test_task_cleanup_errors.das' $true 'Task cleanup error checks OK'
        Check 'tests/test_task_from_async.das' $true 'Task async adapter checks OK'
        Check 'tests/test_task_from_async_lifetime.das' $true 'Task async adapter lifetime checks OK'
        Check 'tests/test_task_from_async_move.das' $true 'Task async move checks OK'
        Check 'tests/test_task.das' $true 'Task checks OK'
        Check 'tests/test_task_result.das' $true 'TaskResult checks OK'
        Check 'tests/test_task_control.das' $true 'Task control checks OK'
        Check 'tests/test_task_lifetime.das' $true 'Task lifetime checks OK'
        Check 'tests/test_task_and_bind.das' $true 'Task and_bind checks OK'
        Check 'tests/test_task_and_bind_lifetime.das' $true 'Task and_bind lifetime checks OK'
        Check 'tests/test_task_extended.das' $true 'Task extended checks OK'
        Check 'tests/test_task_loops.das' $true 'Task loop checks OK'
        Check 'tests/test_task_shared.das' $true 'Task shared checks OK'
        Check 'tests/test_task_deferred.das' $true 'Task deferred checks OK'
        Check 'tests/test_task_owned.das' $true 'Task owned checks OK'
        & (Join-Path $PSScriptRoot 'test_task_tcp.ps1') -Daslang $Daslang
        & (Join-Path $PSScriptRoot 'test_task_tcp.ps1') -Daslang $Daslang -Example
        & (Join-Path $PSScriptRoot 'test_task_hv.ps1') -Daslang $Daslang
        & (Join-Path $PSScriptRoot 'test_task_hv.ps1') -Daslang $Daslang -Example
        & (Join-Path $PSScriptRoot 'test_task_hv.ps1') -Daslang $Daslang -AndBind
        & (Join-Path $PSScriptRoot 'test_task_hv.ps1') -Daslang $Daslang -AndBind -Example
        Check 'tests/test_task_and_bind_unsupported.das' $false 'and_bind is unsupported for builder'
        Check 'tests/test_task_pointer.das' $false 'task: payload must own its data'
        & (Join-Path $PSScriptRoot 'test_diagnostics.ps1') -Daslang $Daslang
        & (Join-Path $PSScriptRoot 'test_integration.ps1') -Daslang $Daslang
        Check 'tests/test_state_operations_failures.das' $true 'State operation failure checks OK'
        Check 'tests/test_composition_laws.das' $true 'Composition laws OK'
        Check 'tests/test_state_operations.das' $true 'State operations OK'
        Check 'tests/test_list_array_finalizer.das' $true 'List custom array finalizer checks OK'
        Check 'tests/test_list_fusion.das' $true 'List fusion effects and ownership OK'
        Check 'tests/test_list_benchmarks.das' $true 'List benchmark equivalence OK'
        Check 'tests/test_state_optimized.das' $true 'State optimized loops checks OK'
        Check 'tests/test_saved_builder.das' $true 'saved builder checks OK'
        Check 'tests/test_saved_builder_missing_protocol.das' $false 'missing ce_protocol'
        Check 'tests/test_benchmark_workloads.das' $true 'benchmark workload equivalence checks OK' 
        Check 'tests/test_coroutine_safety.das' $true 'coroutine scheduler safety checks OK'
        Check 'tests/test_coroutine_slots.das' $true 'coroutine slot checks OK'
        Check 'tests/test_coroutine_scheduler.das' $true 'coroutine scheduler checks OK'
        Check 'tests/test_coroutine.das' $true 'coroutine checks OK'
        Check 'tests/test_state_writer_result.das' $true 'state/writer/result checks OK'
        Check 'tests/test_reader_result.das' $true 'reader/result checks OK'
        Check 'tests/test_reader_result_readonly.das' $false "can't write to a constant value"
        Check 'tests/test_move_resources.das' $true 'move-only resource checks OK'
        Check 'tests/test_move_resource_binding.das' $false 'borrow ownership with'
        Check 'tests/test_move_resource_no_disposer.das' $false 'ce_dispose'
        Check 'tests/test_sequence_next_move.das' $true 'sequence_next_move ownership checks OK'
        Check 'tests/test_sequence_next_move_copy.das' $false 'sequence_next_move requires a move-only element'
        Check 'tests/test_deferred_move_collections.das' $true 'deferred move-only collection checks OK'
        Check 'tests/test_deferred_move_pointer.das' $false 'builder and snapshot must own their data'
        Check 'tests/test_deferred_reference_result.das' $false 'iterator elements must own their data'
        Check 'tests/test_move_collections.das' $true 'move-only collection checks OK'
        Check 'tests/test_move_list_copy.das' $false 'move-only List: use return <- or yield <-'
        Check 'tests/test_move_list_cartesian.das' $false 'Cartesian product requires copyable input elements'
        Check 'tests/test_move_ce.das' $true 'move-only CE checks OK'
        Check 'tests/test_move_bind_move.das' $false 'bind borrows its payload'
        Check 'tests/test_move_copy.das' $false 'use ''return <- value'''
        Check 'tests/test_source_protocol.das' $true 'source protocol checks OK'
        Check 'tests/test_source_void.das' $false 'ce_source must return a source, not void'
        Check 'tests/test_sequence_nested_cleanup.das' $true 'nested Sequence cleanup checks OK'
        Check 'tests/test_fallback_cleanup.das' $true 'fallback cleanup checks OK'
        Check 'tests/test_single_exceptions.das' $true 'single For exception cleanup checks OK'
        Check 'tests/test_zip_cursor_values.das' $true 'zip cursor value checks OK'
        Check 'tests/test_zip_exceptions.das' $true 'zip exception cleanup checks OK'
        Check 'tests/test_zip_readonly.das' $false "left side can't be constant"
        Check 'tests/test_zip_for.das' $true 'zip for checks OK'
        Check 'tests/test_zip_dispatch.das' $true 'zip dispatch checks OK'
        Check 'tests/test_zip_void.das' $false 'loop hook must return a builder outcome'
        Check 'tests/test_loop_void.das' $false 'loop hook must return a builder outcome'
        Check 'tests/test_loop_dispatch.das' $true 'loop dispatch checks OK'
        Check 'tests/test_loop_protocol.das' $true 'loop protocol checks OK'
        Check 'tests/test_deferred_sequence.das' $true 'deferred sequence lifetime checks OK'
        Check 'tests/test_deferred_iterator_pointer.das' $false 'iterator elements must own their data'
        Check 'tests/test_deferred.das' $true 'deferred behavior and lifetime checks OK'
        Check 'tests/test_deferred_snapshots.das' $true 'deferred snapshot checks OK'
        Check 'tests/test_deferred_order.das' $true 'deferred ordering checks OK'
        Check 'tests/test_deferred_capture.das' $false 'can''t locate variable ''local'''
        Check 'tests/test_deferred_pointer.das' $false 'builder and snapshot must own their data'
        Check 'tests/test_deferred_iterator.das' $true 'deferred iterator checks OK'
        Check 'tests/test_deferred_annotation.das' $false 'use an untyped snapshot argument'
        Check 'tests/test_deferred_copy.das' $false 'can only be move-initialized'
        Check 'tests/test_run.das' $true 'run protocol checks OK'
        Check 'tests/test_collect_temporaries.das' $true 'collect temporary checks OK'
        Check 'tests/test_run_void.das' $false 'ce_run must return a value, not void'
        Check 'tests/test_bind2_dispatch.das' $true 'bind2 dispatch checks OK'
        Check 'tests/test_bind2.das' $true 'bind2 value checks OK'
        Check 'tests/test_bind2_list.das' $true 'bind2 list checks OK'
        Check 'tests/test_bind2_return_dispatch.das' $true 'bind2_return dispatch checks OK'
        Check 'tests/test_bind2_return.das' $true 'bind2_return value checks OK'
        Check 'tests/test_bind2_return_list.das' $true 'bind2_return list checks OK'
        Check 'tests/test_effect_bind_return.das' $true 'effect bind_return checks OK'
        Check 'tests/test_bind_return_dispatch.das' $true 'bind_return dispatch checks OK'
        Check 'tests/test_bind_return.das' $true 'bind_return behavior and lifetime checks OK'
        Check 'tests/test_bind_return_types.das' $true 'bind_return type checks OK'
        Check 'tests/test_and_bind.das' $true 'and_bind value checks OK'
        Check 'tests/test_and_bind_list.das' $true 'and_bind list lifetime checks OK'
        Check 'tests/test_and_bind_references.das' $true 'and_bind reference checks OK'
        Check 'tests/test_and_bind_external.das' $true 'and_bind external protocol OK'
        Check 'tests/test_and_bind_arity.das' $false 'expected ''left |> and_bind(right) |> bind'''
        Check 'tests/test_and_bind_mixed.das' $false 'ce_merge_sources'
        Check 'tests/test_and_bind_unsupported.das' $false 'ce_merge_sources'
        Check 'tests/test_and_bind_no_bind.das' $false 'and_bind'
        Check 'tests/test_validation.das' $true 'validation checks OK'
        Check 'tests/test_validation_mixed.das' $false 'ce_unwrap'
        Check 'tests/test_validation_loop_value.das' $false 'ce_loop_append'
        Check 'tests/test_reader.das' $true 'reader checks OK'
        Check 'tests/test_builder_protocol.das' $true 'builder protocol checks OK'
        Check 'tests/test_protocol_missing.das' $false 'missing ce_protocol for builder MissingBuilder'
        Check 'tests/test_protocol_invalid.das' $false 'ce_protocol must return a builder_protocol descriptor'
        Check 'tests/test_protocol_operation.das' $false 'ce_return'
        Check 'tests/test_reader_loop_value.das' $false 'ce_loop_append'
        Check 'tests/test_computation.das' $true 'computation checks OK'
        Check 'tests/test_computation_mixed.das' $false 'ce_unwrap'
        Check 'tests/test_computation_annotation.das' $false 'initialization type mismatch'
        Check 'tests/test_computation_no_return.das' $true 'successful Unit OK'
        Check 'tests/test_computation_control.das' $true 'control flow checks OK'
        Check 'tests/test_computation_return_position.das' $false 'return must be the final statement'
        Check 'tests/test_computation_loop_value.das' $false 'ce_loop_append'
        Check 'tests/test_computation_combine_value.das' $false 'ce_combine'
        Check 'tests/test_computation_loop_mixed.das' $false 'ce_unwrap'
        Check 'tests/test_computation_effects.das' $true 'state/writer checks OK'
        Check 'tests/test_state_wrong_type.das' $false 'ce_unwrap'
        Check 'tests/test_writer_mixed.das' $false 'ce_unwrap'
        Check 'tests/test_writer_loop_value.das' $false 'ce_loop_append'
        Check 'tests/test_state_loop_value.das' $false 'computation_effects::ce_for'
        Check 'tests/test_writer_result.das' $true 'writer/result checks OK'
        Check 'tests/test_writer_result_option.das' $false 'ce_unwrap'
        Check 'tests/test_writer_result_writer.das' $false 'ce_unwrap'
        Check 'tests/test_writer_result_loop_value.das' $false 'ce_loop_append'
        Check 'tests/test_state_result.das' $true 'state/result checks OK'
        Check 'tests/test_state_result_option.das' $false 'ce_unwrap'
        Check 'tests/test_state_result_wrong_type.das' $false 'ce_unwrap'
        Check 'tests/test_state_result_foreign_state.das' $false 'ce_unwrap'
        Check 'tests/test_state_result_loop_value.das' $false 'ce_loop_append'
        Check 'tests/test_computation_resources.das' $true 'resources checks OK'
        Check 'tests/test_resources_no_disposer.das' $false 'ce_dispose'
        Check 'tests/test_resources_cleanup_value.das' $false 'ce_try_finally'
        Check 'tests/test_resources_bad_blocks.das' $false 'try_finally expects two blocks'
        Check 'tests/test_resources_no_binding.das' $false 'expected ''let resource'
        Check 'tests/test_list.das' $true 'list checks OK'
        Check 'tests/test_list_mixed.das' $false 'ce_unwrap'
        Check 'tests/test_list_output_type.das' $false 'ce_return'
        Check 'tests/test_list_annotation.das' $false 'initialization type mismatch'
        Check 'tests/test_sequence.das' $true 'sequence checks OK'
        Check 'tests/test_list_yield.das' $true 'list yield checks OK'
        Check 'tests/test_sequence_type.das' $false 'can only copy compatible type'
        Check 'tests/test_sequence_return.das' $false 'sequence: use yield'
        Check 'tests/test_sequence_resource.das' $true 'sequence resource checks OK'
        Check 'tests/test_sequence_resource_binding.das' $false 'expected ''let resource'
        Check 'tests/test_sequence_no_disposer.das' $false 'ce_dispose'
        Check 'tests/test_sequence_cleanup_type.das' $false 'ce_sequence_scoped'
        Check 'tests/test_sequence_cleanup_blocks.das' $false 'try_finally expects two blocks'
        Check 'tests/test_sequence_capture.das' $false 'implicit capture by move requires unsafe'
        Check 'tests/test_sequence_shared.das' $true 'sequence shared capture checks OK'
        Check 'tests/test_sequence_shared_lifetime.das' $true 'sequence cell lifetime checks OK'
        Check 'tests/test_sequence_shared_type.das' $false 'initialization type mismatch'
        Check 'tests/test_sequence_shared_owned.das' $false 'shared locals require copyable values'
        Check 'tests/test_try_with.das' $true 'try_with eager checks OK'
        Check 'tests/test_recover_portability.das' $true 'Recover portability checks OK'
        Check 'tests/test_sequence_try_with.das' $true 'try_with sequence checks OK'
        Check 'tests/test_try_with_lifetime.das' $true 'try_with lifetime checks OK'
        Check 'tests/test_try_with_blocks.das' $false 'try_with expects a body block'
        Check 'tests/test_try_with_arguments.das' $false 'handler takes one string message'
        Check 'tests/test_try_with_message_type.das' $false 'ce_try_with'
        Check 'tests/test_try_with_output_type.das' $false 'ce_try_with'
        $bindReturnExpansion = (& $Daslang 'examples/bind_return_demo.das' -no-module-cache -log 2>&1) -join "`n"
        if ($LASTEXITCODE -ne 0 -or $bindReturnExpansion -notmatch '// from generic list_builder::ce_list_map\(') {
            throw 'Expected fused List map in BindReturn compiler output.'
        }
        Write-Host 'BindReturn expansion verified: fused List map.'
        $stateExpansion = (& $Daslang 'examples/state_expansion_demo.das' -no-module-cache -log 2>&1) -join "`n"
        if ($LASTEXITCODE -ne 0 -or $stateExpansion -notmatch 'for \( .* in range\(' -or
            $stateExpansion -match 'from generic zip_runtime::ce_zip_cursor|from generic computation_effects::ce_loop_append|from generic computation_effects::ce_loop_failed') {
            throw 'Expected a native State range loop without protected cursor or generic loop folding.'
        }
        Write-Host 'State expansion verified: native range loop.'
        $listExpansion = (& $Daslang 'examples/list_fusion_demo.das' -no-module-cache -log 2>&1) -join "`n"
        if ($LASTEXITCODE -ne 0 -or $listExpansion -notmatch 'from generic list_builder::ce_collect_into\(' -or
            $listExpansion -match 'from generic list_builder::ce_bind\(|from generic list_builder::ce_list_map\(|from generic list_builder::ce_return\(') {
            throw 'Expected one List output buffer without intermediate bind/map arrays.'
        }
        Write-Host 'List expansion verified: one output buffer.'


        Write-Host 'All computation checks passed.'
    }
} finally { Pop-Location }

























