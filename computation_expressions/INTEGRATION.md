# Подключение CE к другому проекту

Нужен установленный Daslang 0.6.4 со стандартной daslib (включая AST-макросы); SDK в экспорт не входит.

Публичные модули физически находятся в lib/. Примеры, тесты, бенчмарки и
демонстрационные builders отделены в examples/, tests/, benchmarks/ и support/.
Можно скопировать только lib или использовать exporter:

```powershell
./export_library.ps1 -Destination C:/my_project/ce_example
daslang.exe C:/my_project/ce_example/main.das -no-module-cache
```

Destination должен быть новым каталогом. Поставка содержит lib с 27 модулями,
manifest.json с SHA256, main.das, identity_builder.das, README.md,
[PUBLIC_API.md](PUBLIC_API.md), [TASKS.md](TASKS.md) и
[TASK_COMPOSITION.md](TASK_COMPOSITION.md), [TASK_SCHEDULER.md](TASK_SCHEDULER.md), [TASK_CANCELLATION.md](TASK_CANCELLATION.md), [TASK_DELAY.md](TASK_DELAY.md), [TASK_ARRAY.md](TASK_ARRAY.md), [TASK_AND_BIND.md](TASK_AND_BIND.md). Тестовые builders и type providers не требуются.
Exporter сверяет manifest с фактическим составом lib и его локальными requires.

```das
options gen2
require ./lib/computation.das
[export]
def main() {
    let result=computation(ResultBuilder()) {
        let n=result_ok(20) |> bind
        return n+22
    }
    assert(result as ok==42)
}
```

Requires задавайте относительно исходника, с .das и префиксом ./ или ../:
во вложенном app/main.das это `require ../lib/computation.das`.
Тогда запуск не зависит от текущего рабочего каталога или абсолютного пути
к исходному дереву. Дополнительные подключения и список прикладных операций
приведены в PUBLIC_API.md, включаемом в поставку.

## Минимальный собственный builder

identity_builder.das из шаблона определяет CeValueProtocol, Bind, Unwrap,
Return, Zero и Combine для tuple (value=T). Общие Delay и Run берутся из протокола.
В main.das он используется так:

```das
let custom=computation(IdentityBuilder()) {
    let n=(value=21) |> bind
    return n*2
}
assert(custom.value==42)
```

Менять computation.das и регистрировать builder не нужно. Для and_bind
добавляется ce_merge_sources; для циклов — операции соответствующего протокола.
Служебные курсоры и устройство снимков не являются прикладным API.

test_integration.ps1 проверяет новый экспорт вне исходного дерева: минимальный
builder и smoke с State, ReaderResult, Validation, MoveResult и повторными
deferred List. Тест не использует support или тестовые builders.

Полный Task-контракт: [TASK_COMPLETION.md](TASK_COMPLETION.md).
Сеть подключается отдельным `require ./lib/task_tcp.das`, см. TASK_TCP.md.
AOT host template находится в aot_host/; runner run_aot.ps1 и тестовый manifest
доступны в исходном репозитории, см. AOT_RUNTIME.md.
