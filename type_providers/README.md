# Type providers

Все модули, примеры и тесты провайдеров находятся в этой папке.
`schemas/` содержит схемы, `data/` — входные JSON, `tests/` — ошибочную схему для отрицательного теста.

- `json_provider.das`: генерация структуры из схемы; пример `main.das`.
- [ERASED.md](ERASED.md): стираемые типы и ленивое чтение схем; пример `erased_demo.das`.
- [NATIVE.md](NATIVE.md): ленивая генерация настоящих типов; `lazy_native_provider.das`, пример `native_demo.das`.

```powershell
cd C:\src\dascript_macro_fsharp\type_providers
./run.ps1 -Test
./measure_lazy.ps1 -Count 10000
./measure_native.ps1 -Count 10000
```

Из исходников этой папки используются `require json_provider` или `require lazy_native_provider`.
При прямом запуске примеров рабочим каталогом должна быть эта папка: runtime читает `data/` относительно него.
Computation expressions не требуются.