# Настройка окружения

Что поставить и как настроить, чтобы собирать проект и нормально работать с
модулями C++ в VS Code.

> Своего `CMakeLists.txt` у проекта пока нет. Раздел «Сборка» описывает, как
> будет устроено, и проверен на игрушечном проекте с теми же видами модулей.

---

## 1. Что нужно

| Инструмент | Версия | Зачем |
|---|---|---|
| clang | ≥ 20 | компилятор (см. раздел 2 — почему именно он для отладки) |
| GCC | ≥ 15 | второй компилятор, по желанию |
| CMake | ≥ 3.28 | первая версия с официальной поддержкой модулей |
| Ninja | ≥ 1.11 | с модулями CMake работает только через Ninja (и Visual Studio), не через Makefile |
| clangd | ≥ 20 | языковой сервер для VS Code: подсветка, переходы, ошибки на лету |
| VS Code | — | расширение **clangd** (`llvm-vs-code-extensions.vscode-clangd`) |

Fedora:

```sh
sudo dnf install clang clang-tools-extra cmake ninja-build gcc-c++
```

(`clang-tools-extra` — пакет, в котором лежит clangd.)

---

## 2. Известные проблемы инструментов

Проверено 29.10.2026 на игрушечном проекте: модуль с global module fragment,
интерфейсный и внутренний разделы, файл реализации, экспортированный шаблон,
второй модуль, импортирующий первый, тесты на GoogleTest.

| | GCC 15.2 | clang 20.1 |
|---|---|---|
| Сборка модулей | ✅ | ✅ |
| AddressSanitizer (`-fsanitize=address`) | ✅ | ✅ |
| UndefinedBehaviorSanitizer (`-fsanitize=undefined`) | ❌ компилятор падает | ✅ |
| GoogleTest + `import` | ✅ | ✅ |
| Пересборка только зависимых файлов | ✅ | ✅ |
| clangd (с флагом из раздела 4) | ✅ | ✅ |

**GCC + UBSan.** GCC 15 падает с `internal compiler error` в `cp/module.cc`, если
в модуле используется тип из стандартной библиотеки (например, `std::vector` в
сигнатуре экспортированной функции) и включён UBSan. Падение вызывают почти все
подпроверки UBSan, отключить одну проблемную не получится. Поэтому отладочную
сборку с санитайзерами собираем clang'ом. На GCC можно собирать только с ASan.

---

## 3. Сборка

```sh
cmake -S . -B build -G Ninja -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_BUILD_TYPE=Debug
ninja -C build
ctest --test-dir build
```

- Каталог сборки называем именно **`build/`**: clangd сам ищет
  `compile_commands.json` в `build/` рядом с исходниками. При другом имени
  clangd откроет файлы с флагами по умолчанию, и `import` станет для него
  неизвестным словом.
- Сборку GCC держим в отдельном каталоге, например `build-gcc/`.

---

## 4. clangd в VS Code

### 4.1. Отключить IntelliSense от Microsoft

Если стоит расширение C/C++ от Microsoft, его анализатор конфликтует с clangd.
В `settings.json` (`Ctrl+Shift+P` → «Preferences: Open User Settings (JSON)»):

```json
"C_Cpp.intelliSenseEngine": "disabled",
```

### 4.2. Включить поддержку модулей

```json
"clangd.arguments": [
    "--background-index",
    "--experimental-modules-support"
],
```

Без `--experimental-modules-support` clangd не видит модули, если проект собран
GCC. С флагом clangd сам строит свои BMI (скомпилированные интерфейсы модулей) из
исходников, и ему всё равно, каким компилятором собран проект.

### 4.3. Только если собираете GCC

CMake записывает в `compile_commands.json` флаги модулей для GCC, которых clangd
не понимает. Их нужно убрать в `~/.config/clangd/config.yaml`:

```yaml
# CMake >= 3.28 adds GCC-only C++ modules flags to compile_commands.json;
# clang does not know them and then misdetects the libstdc++ headers.
CompileFlags:
  Remove: [-fmodules-ts, -fmodule-mapper=*, -fdeps-format=*]
```

После изменения настроек: `Ctrl+Shift+P` → «clangd: Restart language server».

---

## 5. Подсветка `import` и имён модулей

Встроенная грамматика C++ в VS Code красит `export` и `module`, но не `import`:
она знает только форму `import <header>;`. В репозитории лежит маленькое
расширение, которое это исправляет: [tools/vscode-module-decls/](../tools/vscode-module-decls/).

```sh
./tools/vscode-module-decls/build.sh
code --install-extension tools/vscode-module-decls/cpp-module-decls-0.0.1.vsix
```

Затем `Ctrl+Shift+P` → «Developer: Reload Window».

Что оно делает: добавляет к встроенной грамматике правила для `import X;`,
`[export] module X[:part];`, `module;` и `module : private;`. Имена модулей
размечаются как имена пространств имён: какого они будут цвета, зависит от темы.
Удалить: `code --uninstall-extension local.cpp-module-decls`.

---

## 6. Схемы в документации

Схемы в `docs/` нарисованы на Mermaid. GitHub рисует их сам, а в VS Code для
предпросмотра нужно расширение **Markdown Preview Mermaid Support**
(`bierner.markdown-mermaid`).

Проверить схемы локально (по желанию) можно через Mermaid CLI:

```sh
npm install -g @mermaid-js/mermaid-cli
PUPPETEER_EXECUTABLE_PATH=/usr/bin/google-chrome mmdc -i docs/architecture.md -o /tmp/out.md
```

Переменная `PUPPETEER_EXECUTABLE_PATH` нужна, если не хочется, чтобы mmdc
скачивал свой Chromium: тогда он берёт уже установленный Chrome.
