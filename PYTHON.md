# Python Code Standards

## Commands

```bash
uv sync                                  # install / sync dependencies
uv run ruff check --fix . && uv run ruff format .   # before every commit
uv run pytest                            # default suite, live tests excluded
uv run pytest -m live_ssh_test           # one family of live tests, explicitly
uv run --python 3.11 pytest              # the suite on the minimum supported version
```

## Quick reference

Mechanical rules are enforced by ruff (see Ruff configuration). What follows is what ruff cannot check.

- Every name spelled out in full. No abbreviations, no single letters, no exemption for short scope.
- Docstring summary lines are imperative. No trailing periods anywhere in a docstring (ruff enforces the period rule, not the imperative one).
- Fixed sets of string values are a `StrEnum` with ALL_CAPS members, never a set of literals.
- Numeric defaults and thresholds are named module-level constants; unit suffix when the type does not make the unit clear (`_S`, `_MS`, `_CENTS`).
- Type annotations on every signature and every class attribute. Not on local variables. `__init__` and classmethods carry no return annotation.
- Module-level functions are always public. Class internals that callers should not touch are underscore-prefixed.
- Comments are rare and say *what*, never *why*.
- `__init__.py` files are empty. Imports name the module that defines the thing; import one level up when a bare name would be unreadable.
- `attrs` for internal models, `pydantic` v2 for anything that crosses a boundary. Every `attrs` attribute has a validator.
- Use the established library before writing your own.
- Configuration files are TOML. Exceptions are specific, chained, and never swallowed. Logging through `logging.getLogger(__name__)`, never `print`.
- Minimum Python is 3.11. The repo must work on the minimum in `requires-python`, and that minimum must not be higher than the code needs.
- `uv` manages the environment. If the session is not inside the project's `.venv`, warn the user before doing anything else.

## Docstrings

Ruff enforces presence, Google sections, and the no-period rule. These are the parts it does not:

1. The summary line is a single imperative sentence: `Return the…`, `Build the…`, `Send the…`. Not a noun phrase, not third person.
2. `Args:`, `Raises:`, `Returns:` in that order, one line per entry. No types in the docstring; they live in the signature.
3. Module docstrings are one line.

```python
"""Define the Order class"""


def merge_customer_records(primary_record: dict[str, Any], secondary_record: dict[str, Any]) -> dict[str, Any]:
    """Return a single record combining both sources, preferring the primary where they conflict

    Args:
        primary_record: The record whose values win on conflict
        secondary_record: The record used to fill fields the primary lacks

    Raises:
        ValueError: If the two records have different customer identifiers

    Returns:
        One record with every field known from either source
    """
```

Wrong summary lines, for contrast:

```python
"""A single record combining both sources"""         # noun phrase, not imperative
"""Returns a single record combining both sources"""  # third person
```

## Names

Spell every name out in full. This applies to every identifier you write: variables, arguments, attributes, loop variables, comprehension variables, and lambda arguments. There is no exemption for short scope. Ruff's `N` rules check case conventions, not this.

| Wrong | Right |
| --- | --- |
| `cfg` | `config` |
| `tmp` | `temporary_path` |
| `idx`, `i` | `index`, `row_number` |
| `img` | `image` |
| `msg` | `message` |
| `res` | `result` |
| `n` | `count`, `retry_count` |
| `x`, `y` | `left_edge`, `top_edge` |
| `for i in range(...)` | `for attempt_number in range(...)` |
| `[u for u in users]` | `[user for user in users]` |
| `lambda o: o.total` | `lambda order: order.total` |

### Enums for fixed sets of values

When a value can only be one of a fixed set of strings, define a `StrEnum`. Never pass a set or list of string literals around, and never validate against one.

- Members are ALL_CAPS and spelled out in full, like every other name.
- The enum name says what the set is (`Currency`, `OrderStatus`), not `CurrencyEnum` or `CurrencyType`.
- Validate with `validators.instance_of(Currency)`, not `validators.in_({...})`.

```python
# Wrong: literals scattered through the code
currency: str = field(validator=validators.in_({"USD", "EUR", "GBP"}))


# Right: one enum, validated by type
class Currency(StrEnum):
    UNITED_STATES_DOLLAR = "USD"
    EURO = "EUR"
    POUND_STERLING = "GBP"


currency: Currency = field(validator=validators.instance_of(Currency))
```

### Named constants and unit suffixes

`PLR2004` flags bare numbers in comparisons. Go further: every literal default, threshold, or limit is a module-level constant in ALL_CAPS with a name that says what it is for, including in signatures and `field(default=...)`.

Add a unit suffix only when the type alone does not make the unit clear. `int` and `float` say nothing about whether a value is seconds, milliseconds, cents, or dollars, so time and money get a suffix. A `Path`, `Decimal` with a `Currency` beside it, or a `timedelta` already carries its meaning and gets no suffix.

| Wrong | Right |
| --- | --- |
| `timeout: int = 30` | `timeout_s: int = DEFAULT_SSH_CONNECT_TIMEOUT_S` |
| `if elapsed > 500:` | `if elapsed_ms > MAX_RENDER_TIME_MS:` |
| `fee = 250` | `fee_cents = PLATFORM_FEE_CENTS` |
| `retries: int = 3` | `retries: int = DEFAULT_RETRY_COUNT` (a count needs no unit) |

## Type annotations

- Annotate every parameter on every function and method, including private ones and `__init__`.
- Annotate the return type of every function and method, with two exceptions where the return is implied:
  - `__init__` always returns `None`. Do not write `-> None`.
  - A `@classmethod` returns an instance of the class. Do not write `-> Self` or `-> "ClassName"`.
- Annotate every class attribute.
- Do not annotate local variables. Let inference handle them.
- Do not repeat types in docstrings.

The type checker is pyright, which infers the classmethod return correctly. If a repository uses mypy instead, annotate classmethod returns with `-> Self` there, because mypy treats the unannotated return as `Any` and loses the type at every `from_*` constructor.

```python
@define
class OrderBook:
    orders: list[Order] = field(
        validator=validators.deep_iterable(validators.instance_of(Order), validators.instance_of(list)),
    )
    total_value: Decimal = field(init=False, validator=validators.instance_of(Decimal))

    def orders_for(self, customer_id: str) -> list[Order]:
        """Return every order placed by one customer

        Args:
            customer_id: The identifier of the customer to look up

        Returns:
            The matching orders in the order they were placed, empty if there are none
        """
        matching_orders = [order for order in self.orders if order.customer_id == customer_id]  # local: no annotation
        return matching_orders


class Currency(StrEnum):
    UNITED_STATES_DOLLAR = "USD"
    EURO = "EUR"

    @classmethod
    def from_country_code(cls, country_code: str):  # no return annotation: a classmethod returns the class
        """Return the currency used in a country

        Args:
            country_code: The two-letter ISO country code

        Raises:
            ValueError: If the country is not one this system settles in
        """
        ...


class PaymentGateway:
    def __init__(self, api_key: str, timeout_s: int = DEFAULT_GATEWAY_TIMEOUT_S):  # no return annotation
        """Create a gateway bound to one API key

        Args:
            api_key: The secret used to authenticate every request
            timeout_s: How long to wait for the gateway before giving up
        """
        ...
```

## Public module functions, private class internals

Module-level functions are always public. If a piece of logic is worth extracting, it is worth a public name, a full signature, and a docstring. Never prefix a module-level function with an underscore.

```python
# Wrong: hidden, vaguely named, no contract
def _group_once(items, config): ...


# Right: public, named for what it does, fully specified
def group_by_window(events: list[Event], config: WindowConfig) -> list[list[Event]]:
    """Group events into runs that fall within one time window of each other

    Args:
        events: The events in chronological order
        config: The window size to group with

    Returns:
        One list per window, each holding the events that belong together
    """
```

Classes are the opposite. A method or property that callers outside the class have no business using *should* be underscore-prefixed; the prefix is how the class declares its interface. Private methods still get full signatures and docstrings.

```python
@define
class PaymentClient:
    def charge(self, amount: Decimal, customer_id: str) -> Receipt:
        """Charge a customer and return the receipt"""

    def _send_request(self, payload: dict[str, Any]) -> Response:
        """Return the raw response for an already-built payload"""
```

## Comments

Write code that does not need explaining. Comments are the exception, and when one is needed it states **what** something is, never **why** it was written that way. This is deliberate and is the reverse of the usual advice; follow it anyway. `ERA` removes commented-out code; it does not judge the comments that remain.

```python
# Good: names something the code alone cannot tell the reader
# Stripe's idempotency header
IDEMPOTENCY_HEADER_NAME = "Idempotency-Key"

# Good: labels a section of a longer function
# Pass one: collect candidates
...
# Pass two: merge overlapping candidates
...

# Bad: narrates the author's reasoning
# We retry here because the upstream API drops connections under load and
# I found that backing off exponentially worked better than a fixed delay

# Bad: restates a line that is already clear
# The number of attempts left
remaining_attempts: int = field(init=False, validator=validators.instance_of(int))
```

Never write changelog or edit-history comments, `TODO(claude)` or any other attribution comments, or comments that restate the line below them.

## Packages and imports

Ruff bans relative imports (`TID252`) and star imports (`F403`, `F405`), and the pre-commit hook keeps `__init__.py` empty. What remains:

- `__init__.py` exists only to mark a package. Never re-export from it. Every import names the module that defines the thing: `from my_project.orders.models import Order`, not `from my_project.orders import Order`.
- Import at the level that keeps the name readable. A bare imported name must tell the reader what it is and where it came from. Two triggers to import one level up and qualify at the point of use:
  1. The name is meaningless on its own. `ge`, `in_`, `lt`, `matches_re` say nothing without their module. Import `validators` and write `validators.ge`.
  2. Two libraries export similar names. If both `attrs.field` and `pydantic.Field` appear in a file, import the modules and write `attrs.field` and `pydantic.Field`.
- Names that are unambiguous on their own (`Decimal`, `Path`, `define`, `BaseModel`) are imported directly.
- Imports sit under three comment headers, isort-ordered within each; omit a header only when its group is empty.

```python
# Standard libraries
from decimal import Decimal
from enum import StrEnum
from typing import Any

# Third-party libraries
import httpx
from attrs import define, field, validators

# Project libraries
from my_project.config import WindowConfig
```

```python
# Wrong: the reader has to know attrs to recognise these
from attrs.validators import ge, in_, instance_of

count: int = field(validator=[instance_of(int), ge(0)])


# Right: the module name carries the meaning
from attrs import validators

count: int = field(validator=[validators.instance_of(int), validators.ge(0)])


# Wrong: two near-identical names from two libraries
from attrs import field
from pydantic import Field


# Right: qualify both so neither can be mistaken for the other
import attrs
import pydantic

@attrs.define
class Internal:
    count: int = attrs.field(validator=validators.instance_of(int))

class External(pydantic.BaseModel):
    count: int = pydantic.Field(ge=0)
```

## Dataclasses

Choose the library by where the data goes:

- `attrs` (`@define`, `field`) for internal models: anything constructed and consumed only inside the codebase.
- `pydantic` v2 (`BaseModel`) for anything that crosses a boundary: request or response bodies, configuration loaded from files, JSON parsing or validation, and any model another service consumes. Use the v2 API only: `model_validate`, `model_dump`, `field_validator`, `model_validator`, `ConfigDict`. Never use v1 names (`parse_obj`, `.dict()`, `@validator`, `class Config`) or the `pydantic.v1` compatibility module.

Do not use the standard-library `dataclasses` module.

### attrs validators

Every attribute on an `attrs` class declares a validator. No attribute is left as a bare annotation or a bare `field()`. Import `validators` from `attrs` and use the built-ins qualified (`validators.instance_of`, `validators.optional`, `validators.deep_iterable`, `validators.deep_mapping`, `validators.in_`, `validators.ge`, `validators.gt`, `validators.le`, `validators.lt`, `validators.matches_re`, `validators.min_len`, `validators.max_len`); combine them with `validators.and_` or a list when one is not enough. When no built-in expresses the constraint, write a validator function: a public module-level function with a full signature and docstring, taking `(instance, attribute, value)` and raising `ValueError`.

```python
def validate_positive_decimal(instance: object, attribute: Attribute, value: Decimal) -> None:
    """Raise if a decimal attribute is not strictly positive

    Args:
        instance: The object being validated
        attribute: The attribute being set
        value: The value proposed for the attribute

    Raises:
        ValueError: If the value is zero or negative
    """
    if value <= 0:
        raise ValueError(f"{attribute.name} must be positive, got {value}")


# Internal: attrs, every attribute validated
@define
class OrderBook:
    orders: list[Order] = field(
        validator=validators.deep_iterable(validators.instance_of(Order), validators.instance_of(list)),
    )
    currency: Currency = field(validator=validators.instance_of(Currency))
    settlement_delay_s: int = field(
        default=DEFAULT_SETTLEMENT_DELAY_S,
        validator=[validators.instance_of(int), validators.ge(0)],
    )
    total_value: Decimal = field(init=False, validator=[validators.instance_of(Decimal), validate_positive_decimal])


# Crosses a boundary: pydantic
class CreateOrderRequest(BaseModel):
    customer_id: str
    line_items: list[LineItem]
```

## Error handling

- Raise specific exceptions. Each package defines its own hierarchy rooted in one base (`class OrderError(Exception)`), with subclasses for each failure a caller might handle differently (`OrderNotFoundError`, `InsufficientStockError`). Callers catch the base when they do not care which, the subclass when they do.
- Never `except Exception:` or bare `except:` except at the outermost boundary of a process (a CLI entry point, a request handler), and there only to log and convert to an exit code or error response.
- Never swallow. An `except` block either re-raises, raises a more specific exception, or returns a value that the caller is documented to expect. `except SomeError: pass` is wrong.
- Chain when translating: `raise OrderNotFoundError(order_id) from error`, never a bare `raise NewError(...)` inside an `except`, so the original traceback survives.
- Keep `try` blocks small: only the call that can raise, not the surrounding logic.
- Every exception a function raises on purpose is listed under `Raises:` in its docstring.
- Do not use exceptions for control flow that a return value expresses better. A lookup that may legitimately find nothing returns `None` or an empty collection; a lookup that must succeed raises.

```python
# Wrong: broad, swallowed, unchained
try:
    order = repository.load(order_id)
    total = compute_total(order)
except Exception:
    total = Decimal("0")


# Right: narrow try, specific exception, chained translation
try:
    order = repository.load(order_id)
except KeyError as error:
    raise OrderNotFoundError(order_id) from error
total = compute_total(order)
```

## Logging

- Use the standard-library `logging`. One module-level logger per file: `logger = logging.getLogger(__name__)`. Never `print` outside a CLI's final user-facing output.
- Libraries and packages never configure logging (no `basicConfig`, no handlers). Only the entry point of a process configures it.
- Use lazy formatting: `logger.info("Charged %s to customer %s", amount, customer_id)`, not an f-string, so the message is only built when the level is enabled.
- Levels: `DEBUG` for detail useful only when diagnosing; `INFO` for state changes worth seeing in normal operation; `WARNING` for something wrong that the code handled; `ERROR` for something wrong that it could not handle. Do not log at `ERROR` and then raise; either log-and-handle or raise, not both.
- Log the exception with `logger.exception(...)` inside an `except` block when the exception is being handled there, so the traceback is captured.
- Never log secrets, tokens, passwords, or full request bodies that might contain them.

## Use the library that exists

Do not write from scratch what a well-maintained library already does. Before building any piece of infrastructure, check whether the ecosystem has a standard answer, and use it.

| Do not write | Use instead |
| --- | --- |
| Your own request validation on top of Flask | FastAPI with pydantic models |
| Your own fake HTTP transport or patched `httpx` internals | `pytest-httpx` (or `respx`), the library's own test tooling |
| A retry loop with hand-written backoff | `tenacity` |
| A hand-parsed `sys.argv` or a bare `argparse` tree for a real CLI | `typer` (or `click`) |
| Your own `.env` / environment-variable loader | `pydantic-settings` |

If a library does most of the job but not all of it, wrap it in an adapter this codebase owns and add the missing piece there. Do not fork or reimplement it.

## Configuration files

Configuration this codebase reads or writes is TOML, not JSON, YAML, or INI.

- Read with the standard-library `tomllib` (the minimum Python is 3.11, so it is always available).
- Write with `tomlkit`, which round-trips comments and formatting. `tomllib` is read-only.
- Model the parsed result with a pydantic model (configuration crosses a boundary) so a malformed file fails at load time with a clear message.

## Supported Python versions

The floor for every project is 3.11 (`StrEnum` and `tomllib` require it). `requires-python` in `pyproject.toml` is a promise; keep it true in both directions.

- **The code must run on the minimum.** Before finishing any change that touches syntax, the standard library, or dependencies, run the suite on the lowest supported version: `uv run --python 3.11 pytest` (use `uv python install 3.11` first if it is missing). Do not rely on the version that happens to be active.
- **The minimum must not be higher than the code needs.** A project that runs on 3.11 must not declare `>=3.13`. Only raise the minimum when a specific feature requires it, say which feature in the commit message, and check for a backport (`typing_extensions`, `exceptiongroup`) first.
- Ruff's `target-version` is always the lowest version in `requires-python`, so `UP` rules never rewrite code into syntax the minimum cannot run.
- When you find a mismatch in either direction, fix it or flag it; do not leave it.

## Environment

Every project uses `uv` for its virtual environment and dependencies. Do not use `pip`, `venv`, `poetry`, `conda`, or `pipenv` unless the repo already does and the user has said to keep it.

- Install or sync with `uv sync`; add or remove with `uv add` / `uv remove` so `pyproject.toml` and `uv.lock` stay in step. Never `pip install` into the environment.
- Run tools through the environment: `uv run pytest`, `uv run ruff check .`, `uv run python script.py`.

Before running any Python, tests, or linters, check that the session is inside the project's environment: `VIRTUAL_ENV` should point at the project's `.venv`, and `which python` should resolve inside it. If it does not, stop and tell the user, in these terms:

> This session is not running inside the project's `.venv`. Activate it (`source .venv/bin/activate`, or `uv venv` first if it does not exist), then restart the session or terminal that Claude is running in so the new environment is picked up. Commands run before that will use the wrong interpreter.

Do not work around a missing environment by installing packages globally or by calling a system `python`.

## Testing

Tests are `pytest`, live under `tests/`, and mirror the source tree. The package sits at the repo root as `<package_name>/`, not under `src/`: `my_project/orders/models.py` is tested by `tests/orders/test_models.py`. Every rule in this file applies to test code too.

### What tests are for

A test suite exists to prove the tool does what it is for. It does not exist to prove that each function performs a narrow set of actions, and it does not exist to reach a coverage number.

- Start from the behaviour the tool must deliver and the ways it can realistically fail in the field. Write tests that prove those things. Only then add unit tests where there is isolated logic worth pinning; never write a unit test per function as a matter of routine.
- For anything that talks to the outside world, the live tests are the primary tests, not an optional extra. An SSH connection manager is not tested by unit tests of its string parsing; it is tested by connecting to a real host and hitting the real failure modes: host key changes, missing agent, dropped connection mid-command, timeouts, a remote shell that is not bash. The `live_<system>_test` marker controls *when* those tests run, not *whether* they are written.
- Coverage is not a metric and never a target. A line executed is not a line verified; a suite can reach 100% and check nothing. Do not cite a coverage percentage as evidence that something is tested, and do not add tests to raise a number. Use a coverage report only to find code nothing exercises at all.

### Robust tests, not brittle ones

Assert on what the function promises, not on how the result happens to look. Before every assertion ask: if this detail changed, would a caller break? If the answer is no, do not assert on it. A test that fails when nothing is wrong teaches people to edit the assertion instead of thinking, and eventually to ignore the suite.

Brittle assertions to avoid:

- Exact string output when the string is not a defined format. Parse the result and assert on the values.
- List order when order is not part of the contract. Compare as a set, or sort both sides.
- Exception message text. Assert on the exception type, and on a specific attribute of it if the contract defines one.
- Log message text.
- Floating-point equality without `pytest.approx`.
- Private attributes or internal state of the object under test.
- Call counts or arguments on internal collaborators (see Mocking).

The carve-out: when the exact representation *is* the contract (a file format, a wire protocol, CLI output that scripts parse, an identifier scheme), assert on it exactly, and state that contract in the function's docstring so the strict assertion is visibly justified.

```python
# Wrong: pinned to formatting the function never promised
def test_get_client_list_returns_clients() -> None:
    """Check that the client list contains the registered clients"""
    manager = ClientManager(registry=FakeRegistry(client_identifiers=[1, 2, 3, 4]))

    client_list = manager.get_client_list()

    assert client_list == "1,2,3,4"


# Right: asserts on the promise, survives a change of separator, spacing, or order
def test_get_client_list_returns_every_registered_client() -> None:
    """Check that the client list names every registered client and nothing else"""
    manager = ClientManager(registry=FakeRegistry(client_identifiers=[1, 2, 3, 4]))

    client_list = manager.get_client_list()

    listed_identifiers = {int(identifier) for identifier in client_list.split(",")}
    assert listed_identifiers == {1, 2, 3, 4}
```

### Live tests

Most tests run entirely in memory and need no marker. Any test that touches a live system is the exception, and it is marked and excluded from the default run so nobody triggers it by accident.

A live test is one that needs anything outside the process: a network connection, a real service, an SSH host, a database, a cloud API, credentials, or another machine.

- Mark each live test with a marker named `live_<system>_test`, where `<system>` names the thing it talks to: `live_ssh_test`, `live_postgres_test`, `live_s3_test`. One marker per external system the test needs; a test that needs two gets both.
- Register every marker in `pyproject.toml` with a one-line description, and set `--strict-markers` so an unregistered marker is an error rather than a silent no-op.
- Exclude all live markers from the default invocation so plain `uv run pytest` never runs them. Run them explicitly with `uv run pytest -m live_ssh_test`.
- Never put a live test in a pre-commit hook.
- When adding the first live test for a new system, add the marker registration and the default exclusion in the same change.

```toml
[tool.pytest.ini_options]
addopts = "--strict-markers -m 'not live_ssh_test and not live_postgres_test'"
markers = [
    "live_ssh_test: needs a reachable SSH host and credentials",
    "live_postgres_test: needs a running PostgreSQL instance",
]
```

```python
@pytest.mark.live_ssh_test
def test_run_command_returns_remote_stdout() -> None:
    """Check that running a command over SSH returns what the remote host printed"""
    ...
```

### Mocking

Follow "don't mock what you don't own." The rule is about who writes the double, not about whether a third-party library is involved. A double you hand-write for someone else's library is a guess at how that library behaves; a double the library ships for itself runs the library's real code against controlled inputs. Prefer the second, and never patch the library's internals yourself.

In order of preference:

1. **Use the library's own supported test tooling when it exists.** `pytest-httpx` or `respx` for `httpx`, `responses` for `requests`, `moto` for `boto3`, `freezegun` or `time-machine` for the clock, `fakeredis` for Redis, `pyfakefs` for the filesystem. These replace the transport or backend underneath the real client, so the real exception types, status handling, retries, and decoding are exercised. Testing "what happens on a 503" against `pytest-httpx` tests the actual `httpx.HTTPStatusError` path; testing it against a `Mock` tests whatever you imagined.
2. **Otherwise, wrap the dependency in an adapter this codebase owns and replace the adapter.** For dependencies with no supported test tooling (a vendor SDK, an SSH library, an internal service), define an adapter class exposing only the operations the code needs, and have tests supply a hand-written fake: a real class implementing the same interface, holding state in memory. Prefer that over `unittest.mock.Mock` or `MagicMock`. The adapter itself is covered by a live test against the real dependency, so the fake and the real thing cannot drift apart silently.
3. **Never `patch` a function or attribute inside a module you did not write.** `patch("httpx.Client.get")`, `patch("boto3.client")`, `patch("time.sleep")` are all wrong. Reach for option 1 or 2.
4. **Never patch internals of the code under test.** If a test needs to reach inside a class to make it testable, the class needs a dependency injected, not a patch.

```python
# Wrong: patching a library this codebase does not own
def test_charge_sends_amount(mocker: MockerFixture) -> None:
    """Check that charging a customer posts the amount to the gateway"""
    post = mocker.patch("httpx.Client.post")
    PaymentClient(api_key="key").charge(Decimal("10.00"), customer_id="customer_1")
    post.assert_called_once()


# Right (option 1): the library's own test tooling, so real httpx error handling runs
def test_charge_raises_gateway_error_on_server_failure(httpx_mock: HTTPXMock) -> None:
    """Check that a 503 from the gateway surfaces as a GatewayError"""
    httpx_mock.add_response(status_code=503)
    client = PaymentClient(api_key="key")

    with pytest.raises(GatewayError):
        client.charge(Decimal("10.00"), customer_id="customer_1")


# Right (option 2): no supported tooling exists, so an adapter this codebase owns, replaced by a fake it owns
class FakePaymentGateway:
    """Record charges in memory instead of calling the real gateway"""

    def __init__(self):
        """Start with no recorded charges"""
        self.charges: list[tuple[Decimal, str]] = []

    def charge(self, amount: Decimal, customer_id: str) -> Receipt:
        """Record the charge and return a receipt for it

        Args:
            amount: The amount to charge
            customer_id: The customer to charge

        Returns:
            A receipt whose identifier is the position of this charge in the log
        """
        self.charges.append((amount, customer_id))
        return Receipt(identifier=str(len(self.charges)))


def test_charge_records_amount_against_customer() -> None:
    """Check that charging a customer records the amount against that customer"""
    gateway = FakePaymentGateway()
    client = PaymentClient(gateway=gateway)

    client.charge(Decimal("10.00"), customer_id="customer_1")

    assert gateway.charges == [(Decimal("10.00"), "customer_1")]
```

### Structure and naming

- Test function names are `test_<behaviour>_<condition>`, spelled out in full: `test_merge_prefers_primary_on_conflict`, not `test_merge_1`.
- Every test function has a one-line docstring stating what it checks. Imperative, no trailing period, like every other docstring.
- One behaviour per test. If a test name needs "and", split it.
- Arrange, act, assert, in that order, with a blank line between each. No assertions before the act.
- Assert on outcomes (return values, state in a fake, raised exceptions), not on how the code got there. `assert_called_with` on an internal call is a test of the implementation, not the behaviour, and is wrong.
- Shared setup goes in fixtures in `conftest.py`. A fixture used by one file lives in that file.
- No conditionals or loops inside a test. Use `pytest.mark.parametrize` with named `ids` when the same behaviour needs several inputs.
