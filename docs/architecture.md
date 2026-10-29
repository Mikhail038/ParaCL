# Архитектура компилятора ParaCL

Как устроен компилятор: из каких частей он состоит, что между ними передаётся и
кто от кого зависит. Почему устроено именно так — в [decisions.md](decisions.md);
вопросы к самому языку — в [language.md](language.md).

> **Статус: черновик.** Схема опирается на принятые решения 1–4. Отдельное
> типизированное дерево (`paracl.typed`, раздел 3) пока только предложено, выбор
> бэкенда отложен (решение 5).

Цвета во всех схемах одинаковые:
🟪 фронтенд · 🟦 граница между фронтендом и бэкендом · 🟩 бэкенд ·
🟨 файлы и данные · ⬜ внешние инструменты.

---

## 1. Конвейер: что во что превращается

Компилятор — это цепочка стадий. Каждая стадия берёт результат предыдущей и
превращает его в следующее представление программы.

```mermaid
flowchart LR
  SRC("file.pcl")

  subgraph FE["Фронтенд"]
    LEX["lexer"]
    PAR["parser"]
    SEM["sema"]
  end

  TT("типизированное<br/>дерево")

  subgraph BE["Бэкенд"]
    INT["interp"]
    GEN["codegen"]
  end

  RES("вывод программы")
  LL("file.ll")

  SRC --> LEX
  LEX -- "токены" --> PAR
  PAR -- "AST" --> SEM
  SEM --> TT
  TT --> INT
  TT --> GEN
  INT --> RES
  GEN --> LL

  classDef file fill:#FEF3C7,stroke:#D97706,color:#78350F;
  classDef front fill:#F5F3FF,stroke:#7C3AED,color:#4C1D95;
  classDef contract fill:#E0F2FE,stroke:#0369A1,color:#0C4A6E;
  classDef back fill:#DCFCE7,stroke:#16A34A,color:#14532D;

  class SRC,RES,LL file;
  class LEX,PAR,SEM front;
  class TT contract;
  class INT,GEN back;

  style FE fill:#FAF5FF,stroke:#7C3AED,color:#4C1D95
  style BE fill:#F0FDF4,stroke:#16A34A,color:#14532D

  linkStyle default stroke:#6B7280,stroke-width:2px
```

| Стадия | Вход | Выход | Что делает |
|---|---|---|---|
| **lexer** | текст | токены | режет текст на слова языка: `v0`, `:`, `int`, `=`, `5`, `;` |
| **parser** | токены | AST | строит дерево по грамматике, проверяет синтаксис |
| **sema** | AST | типизированное дерево | разрешает имена, выводит и проверяет типы, раскрывает generic-функции |
| **interp** | типизированное дерево | вывод программы | исполняет дерево, рекурсивно обходя его |
| **codegen** | типизированное дерево | `file.ll` | печатает LLVM IR (текстовый промежуточный язык LLVM) |

- **AST** (abstract syntax tree) — дерево программы в том виде, как её написал
  пользователь: без типов, generic-функции ещё не раскрыты.
- **sema** (semantic analysis) — смысловой анализ: всё, что можно проверить до
  запуска.
- **Бэкенд** — последняя стадия, `interp` или `codegen`. Какой из них (или оба)
  будем делать, пока не решено.

Стадиями управляет **driver** (`main.cpp`): разбирает аргументы командной строки,
читает файл, по очереди вызывает стадии и печатает ошибки.

### Если выберем IR: как получить исполняемый файл

`codegen` выдаёт только текст `file.ll`. Исполняемый файл из него собирает `clang`,
дописывая маленький **runtime** — файл на C с функциями ввода/вывода, которые
вызывает сгенерированный код.

```mermaid
flowchart LR
  LL("file.ll")
  RT("runtime.c<br/>input / output")
  CL["clang"]
  EXE("исполняемый файл")

  LL --> CL
  RT --> CL
  CL --> EXE

  classDef file fill:#FEF3C7,stroke:#D97706,color:#78350F;
  classDef tool fill:#E5E7EB,stroke:#4B5563,color:#111827;

  class LL,RT,EXE file;
  class CL tool;
```

---

## 2. Модули и их зависимости

Конвейер выше показывает, **как текут данные**. Модули C++ описывают другое:
**кто кого импортирует**. Стрелка `A → B` означает `A` делает `import B`.

```mermaid
flowchart TB
  PAR["paracl.parser"]
  SEM["paracl.sema"]
  INT["paracl.interp"]
  GEN["paracl.codegen"]
  LEX["paracl.lexer"]
  AST["paracl.ast"]
  TYPED["paracl.typed"]
  TYPES["paracl.types"]

  PAR --> LEX
  PAR --> AST
  SEM --> AST
  SEM --> TYPED
  INT --> TYPED
  GEN --> TYPED
  TYPED -- "export import" --> TYPES

  classDef front fill:#F5F3FF,stroke:#7C3AED,color:#4C1D95;
  classDef contract fill:#E0F2FE,stroke:#0369A1,color:#0C4A6E;
  classDef back fill:#DCFCE7,stroke:#16A34A,color:#14532D;

  class PAR,SEM,LEX,AST front;
  class TYPED,TYPES contract;
  class INT,GEN back;
```

🟪 фронтенд · 🟦 граница · 🟩 бэкенд.

На схеме не показаны два модуля, чтобы не загромождать её:
- `paracl.diag` (позиции в исходнике и сообщения об ошибках) импортируют `lexer`,
  `ast`, `typed` и driver;
- driver импортирует `parser`, `sema`, `interp` и `codegen`.

| Модуль | Что внутри | Импортирует |
|---|---|---|
| `paracl.diag` | позиция в исходнике (файл:строка:столбец), сообщения об ошибках | — |
| `paracl.lexer` | текст → токены | `diag` |
| `paracl.ast` | узлы AST, дамп дерева для тестов | `diag` |
| `paracl.parser` | токены → AST | `lexer`, `ast` |
| `paracl.types` | представление типов: `int(N)`, `double`, массив, структура, тип функции | — |
| `paracl.typed` | узлы типизированного дерева | `diag`, `export import types` |
| `paracl.sema` | AST → типизированное дерево | `ast`, `typed` |
| `paracl.interp` | исполнение типизированного дерева | `typed` |
| `paracl.codegen` | типизированное дерево → `.ll` | `typed` |

**Почему схема такая.**

- **Граф без циклов.** Модули не могут импортировать друг друга по кругу (лекция,
  слайд 56). Все стрелки идут сверху вниз, ни одна не возвращается.
- **Фронтенд и бэкенд не знают друг о друге.** Оба смотрят только на границу. Среди
  импортов `interp` и `codegen` нет ни `ast`, ни `parser`: если бэкенд попытается
  заглянуть в нетипизированное дерево, код не скомпилируется. Аналогия с C:
  функцию из заголовка, который не подключён, вызвать нельзя. Граница из решения 5
  охраняется компилятором, а не договорённостью.
- **`export import types` внутри `typed`** (предложено). Транзитивный импорт (лекция,
  слайд 50): кто импортирует `typed`, автоматически получает и `types`. Узлы
  дерева всё равно бесполезны без типов, поэтому отдельный `import paracl.types` в
  каждом бэкенде был бы лишним.
- **`types` отдельно от `typed`.** Сами типы не должны знать о деревьях. Например,
  `paracl.types` не хранит указатель на тело функции, иначе появится цикл
  `types ↔ typed`.

Точка в `paracl.lexer` — просто часть имени, для языка никакой вложенности она не
означает. Настоящее деление модуля на части — **partitions** (разделы), они пишутся
через двоеточие: `paracl.sema:generics`. Разделы пригодятся, когда `sema` вырастет.

---

## 3. Граница: типизированное дерево

### 3.1. Что меняет sema

Пример из [decisions.md](decisions.md), решение 3:

```pcl
v0 = 0;
v1 : double = v0;
```

```mermaid
flowchart LR
  subgraph BEFORE["AST, после parser"]
    A1["Assign v1"]
    A2["TypeAnnotation double"]
    A3["Var v0"]
    A1 --> A2
    A1 --> A3
  end

  subgraph AFTER["Типизированное дерево, после sema"]
    T1["Assign v1 : double"]
    T2["Convert int(32) → double"]
    T3["Var v0 : int(32)"]
    T1 --> T2
    T2 --> T3
  end

  BEFORE == "sema" ==> AFTER

  classDef front fill:#F5F3FF,stroke:#7C3AED,color:#4C1D95;
  classDef contract fill:#E0F2FE,stroke:#0369A1,color:#0C4A6E;
  classDef added fill:#E0F2FE,stroke:#0369A1,color:#0C4A6E,stroke-width:3px;

  class A1,A2,A3 front;
  class T1,T3 contract;
  class T2 added;

  style BEFORE fill:#FAF5FF,stroke:#7C3AED,color:#4C1D95
  style AFTER fill:#F0F9FF,stroke:#0369A1,color:#0C4A6E

  linkStyle default stroke:#6B7280,stroke-width:2px
```

- У каждого узла появился конкретный тип.
- Неявное преобразование `int → double` стало явным узлом `Convert` (выделен
  жирной рамкой).
- Аннотация `: double` исчезла как отдельный узел: она нужна была только sema.

### 3.2. Что гарантирует граница

Если программа дошла до бэкенда:

1. У каждого выражения есть конкретный тип: `int(16)`, а не «какой-то int».
2. Все неявные преобразования — явные узлы `Convert`.
3. Каждый вызов указывает на конкретную функцию без generic-параметров.
4. Ошибок типов в программе нет.

### 3.3. Как sema раскрывает generic-функции

```pcl
f1 : (x) = { v3 = x + 1; v3 * v3; };
a = f1(2);
b = f1(2.5);
```

```mermaid
flowchart LR
  CALL["вызов<br/>f1(2.5)"]
  KEY["ключ<br/>(f1, [double])"]
  Q{"копия<br/>есть?"}
  CLONE["клонировать<br/>тело f1"]
  CHECK["проверить тело<br/>с x : double"]
  SAVE["сохранить<br/>f1⟨double⟩"]
  USE["вызов<br/>f1⟨double⟩"]

  CALL --> KEY --> Q
  Q -- "нет" --> CLONE
  CLONE --> CHECK --> SAVE --> USE
  Q -- "да" --> USE

  classDef front fill:#F5F3FF,stroke:#7C3AED,color:#4C1D95;
  classDef decision fill:#FEF3C7,stroke:#D97706,color:#78350F;
  classDef contract fill:#E0F2FE,stroke:#0369A1,color:#0C4A6E;

  class CALL,KEY,CLONE,CHECK,SAVE front;
  class Q decision;
  class USE contract;
```

В типизированное дерево попадают только копии `f1⟨int⟩` и `f1⟨double⟩`. Узла
«generic-функция» там нет.

### 3.4. Развилка: отдельное дерево или то же AST

**Статус:** открыто (склоняемся к варианту B)

| | A. Аннотировать то же AST | B. Отдельное дерево `paracl.typed` |
|---|---|---|
| Как | в узлах AST есть поле `type`, sema его заполняет | sema строит новое дерево из других узлов |
| Плюс | одна иерархия узлов, меньше кода | гарантии видны в типах C++: поле типа не может быть пустым, узла generic-функции просто нет |
| Минус | бэкенд получает дерево, где `type` может быть пустым, а generic-узлы существуют. Гарантии держатся на честном слове | два набора узлов, sema переливает одно в другое |

Аналогия с C: в варианте A в структуре есть указатель, который «после такой-то
стадии точно не NULL». В варианте B это другая структура, где такого указателя нет.

Схема модулей в разделе 2 нарисована для варианта B. При варианте A модуль
`paracl.typed` исчезает, и бэкенд импортирует `paracl.ast`.

---

## 4. Тесты по слоям

Каждую стадию можно тестировать отдельно, не дожидаясь остальных.

| Стадия | Вид теста | Что проверяет |
|---|---|---|
| lexer | юнит-тест | текст → ожидаемая последовательность токенов |
| parser | golden-тест | дамп AST совпадает с сохранённым эталоном |
| sema | ill-formed тест | неправильная программа отвергается с ожидаемой ошибкой |
| interp / codegen | end-to-end | `.pcl` + `.in` → вывод совпадает с `.out` |
| interp + codegen | дифференциальный | оба бэкенда дают одинаковый вывод на одной программе |

- **Golden-тест** — сравнение вывода с заранее сохранённым правильным файлом.
- **Ill-formed тест** — программа, которую компилятор обязан отвергнуть. Тест
  проверяет, что ошибка есть и что она та самая (категории — в
  [language.md](language.md), раздел 0).
- **Дифференциальный тест** имеет смысл, только если будут оба бэкенда.

---

## Открытые вопросы

- [ ] Вариант A или B для типизированного дерева (раздел 3.4).
- [ ] `export import paracl.types` внутри `paracl.typed` (раздел 2).
- [ ] `paracl.diag`: останавливаться на первой ошибке или собирать все?
- [ ] Выбор бэкенда ([decisions.md](decisions.md), решение 5).

---

*Draft prepared with help of Claude.*
