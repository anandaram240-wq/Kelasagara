/**
 * RFC 8785 - JSON Canonicalization Scheme (JCS) Implementation
 *
 * Implements deterministic canonical JSON serialization as specified in RFC 8785:
 * 1. Object keys are sorted lexicographically by UTF-16 code units.
 * 2. No insignificant whitespace (no spaces between keys, colons, or commas).
 * 3. Primitive values: null, boolean, numbers without trailing zeros, minimal escapes for strings.
 * 4. Strict rejection of NaN, Infinity, -Infinity.
 * 5. Strict rejection of lone surrogates (unpaired UTF-16 surrogates).
 * 6. Strict detection and rejection of duplicate property names in raw JSON input.
 * 7. Safe integer boundary enforcement ([Number.MIN_SAFE_INTEGER, Number.MAX_SAFE_INTEGER]).
 * 8. Deterministic cross-platform SHA-256 digest computation.
 */

import { createHash } from 'crypto';

export class Rfc8785CanonicalizationError extends Error {
  constructor(message: string) {
    super(`RFC8785_CANONICALIZATION_ERROR: ${message}`);
    this.name = 'Rfc8785CanonicalizationError';
  }
}

/**
 * Checks whether a string contains any unpaired (lone) UTF-16 surrogate code units.
 * RFC 8785 Section 3.2.2.2 strictly forbids lone surrogates in JSON strings.
 */
export function hasLoneSurrogates(str: string): boolean {
  for (let i = 0; i < str.length; i++) {
    const code = str.charCodeAt(i);
    // High surrogate: 0xD800 - 0xDBFF
    if (code >= 0xd800 && code <= 0xdbff) {
      if (i + 1 >= str.length) {
        return true; // Unpaired trailing high surrogate
      }
      const nextCode = str.charCodeAt(i + 1);
      if (nextCode >= 0xdc00 && nextCode <= 0xdfff) {
        i++; // Valid surrogate pair, skip low surrogate
      } else {
        return true; // High surrogate not followed by low surrogate
      }
    } else if (code >= 0xdc00 && code <= 0xdfff) {
      return true; // Unpaired low surrogate
    }
  }
  return false;
}

/**
 * Serializes any JSON-compatible JavaScript value to its canonical RFC 8785 representation.
 */
export function canonicalizeJson(value: any): string {
  if (value === null) {
    return 'null';
  }

  const type = typeof value;

  if (type === 'boolean') {
    return value ? 'true' : 'false';
  }

  if (type === 'number') {
    if (!Number.isFinite(value)) {
      throw new Rfc8785CanonicalizationError(
        `Non-finite numbers (NaN, Infinity, -Infinity) are strictly rejected by RFC 8785. Got: ${value}`
      );
    }
    // Check safe integer boundaries to prevent silent precision loss
    if (Number.isInteger(value)) {
      if (value < Number.MIN_SAFE_INTEGER || value > Number.MAX_SAFE_INTEGER) {
        throw new Rfc8785CanonicalizationError(
          `Integer value ${value} exceeds safe integer range [${Number.MIN_SAFE_INTEGER}, ${Number.MAX_SAFE_INTEGER}]. Represent as string for cryptographic stability.`
        );
      }
    }
    // In ECMAScript / RFC 8785, -0 must serialize to 0
    if (Object.is(value, -0)) {
      return '0';
    }
    return JSON.stringify(value);
  }

  if (type === 'string') {
    if (hasLoneSurrogates(value)) {
      throw new Rfc8785CanonicalizationError(
        'RFC 8785 violation: Lone surrogate code unit detected in string.'
      );
    }
    return JSON.stringify(value);
  }

  if (Array.isArray(value)) {
    const serializedElements = value.map((elem) => {
      // In JSON arrays, undefined, functions, and symbols serialize to null
      if (elem === undefined || typeof elem === 'symbol' || typeof elem === 'function') {
        return 'null';
      }
      return canonicalizeJson(elem);
    });
    return `[${serializedElements.join(',')}]`;
  }

  if (type === 'object') {
    // Sort keys lexicographically by UTF-16 code units (ASCII / code unit order)
    const keys = Object.keys(value).sort((a, b) => {
      if (a === b) return 0;
      return a < b ? -1 : 1;
    });

    const pairs: string[] = [];
    for (const key of keys) {
      if (hasLoneSurrogates(key)) {
        throw new Rfc8785CanonicalizationError(
          `RFC 8785 violation: Lone surrogate code unit detected in object key '${key}'.`
        );
      }
      const val = value[key];
      // Keys with undefined, function, or symbol values are omitted in JSON objects
      if (val === undefined || typeof val === 'function' || typeof val === 'symbol') {
        continue;
      }
      pairs.push(`${JSON.stringify(key)}:${canonicalizeJson(val)}`);
    }
    return `{${pairs.join(',')}}`;
  }

  throw new Rfc8785CanonicalizationError(`Unsupported data type for JSON canonicalization: ${type}`);
}

/**
 * Computes the SHA-256 digest of the RFC 8785 canonical bytes of a value.
 */
export function computeJcsSha256(value: any): string {
  const canonicalString = canonicalizeJson(value);
  return createHash('sha256').update(Buffer.from(canonicalString, 'utf8')).digest('hex');
}

/**
 * Parses raw JSON string while strictly checking for and rejecting duplicate property names.
 * Standard JSON.parse silently overwrites earlier keys ("last key wins").
 * RFC 8785 conformance requires detecting duplicate properties when establishing conformance
 * from serialized input.
 */
export function parseJsonRejectingDuplicates(rawJson: string): any {
  let index = 0;

  function skipWhitespace(): void {
    while (index < rawJson.length) {
      const ch = rawJson[index];
      if (ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r') {
        index++;
      } else {
        break;
      }
    }
  }

  function parseValue(): any {
    skipWhitespace();
    if (index >= rawJson.length) {
      throw new Rfc8785CanonicalizationError('Unexpected end of JSON input');
    }

    const ch = rawJson[index];

    if (ch === '{') {
      return parseObject();
    }
    if (ch === '[') {
      return parseArray();
    }
    if (ch === '"') {
      return parseString();
    }
    if (ch === 't' && rawJson.startsWith('true', index)) {
      index += 4;
      return true;
    }
    if (ch === 'f' && rawJson.startsWith('false', index)) {
      index += 5;
      return false;
    }
    if (ch === 'n' && rawJson.startsWith('null', index)) {
      index += 4;
      return null;
    }
    if (ch === '-' || (ch >= '0' && ch <= '9')) {
      return parseNumber();
    }

    throw new Rfc8785CanonicalizationError(`Unexpected character '${ch}' at position ${index}`);
  }

  function parseString(): string {
    if (rawJson[index] !== '"') {
      throw new Rfc8785CanonicalizationError(`Expected '"' at position ${index}`);
    }
    index++; // skip open quote
    let result = '';

    while (index < rawJson.length) {
      const ch = rawJson[index];
      if (ch === '"') {
        index++; // skip closing quote
        if (hasLoneSurrogates(result)) {
          throw new Rfc8785CanonicalizationError(
            'RFC 8785 violation: Lone surrogate code unit detected in string literal.'
          );
        }
        return result;
      }
      if (ch === '\\') {
        index++;
        if (index >= rawJson.length) {
          throw new Rfc8785CanonicalizationError('Unterminated escape sequence in string');
        }
        const esc = rawJson[index];
        if (esc === '"' || esc === '\\' || esc === '/') {
          result += esc;
          index++;
        } else if (esc === 'b') {
          result += '\b';
          index++;
        } else if (esc === 'f') {
          result += '\f';
          index++;
        } else if (esc === 'n') {
          result += '\n';
          index++;
        } else if (esc === 'r') {
          result += '\r';
          index++;
        } else if (esc === 't') {
          result += '\t';
          index++;
        } else if (esc === 'u') {
          index++;
          const hex = rawJson.substring(index, index + 4);
          if (hex.length < 4 || !/^[0-9a-fA-F]{4}$/.test(hex)) {
            throw new Rfc8785CanonicalizationError(`Invalid Unicode escape '\\u${hex}' at position ${index}`);
          }
          result += String.fromCharCode(parseInt(hex, 16));
          index += 4;
        } else {
          throw new Rfc8785CanonicalizationError(`Invalid escape character '\\${esc}' at position ${index}`);
        }
      } else {
        result += ch;
        index++;
      }
    }

    throw new Rfc8785CanonicalizationError('Unterminated string in JSON input');
  }

  function parseNumber(): number {
    const start = index;
    if (rawJson[index] === '-') {
      index++;
    }
    while (index < rawJson.length && rawJson[index] >= '0' && rawJson[index] <= '9') {
      index++;
    }
    if (index < rawJson.length && rawJson[index] === '.') {
      index++;
      while (index < rawJson.length && rawJson[index] >= '0' && rawJson[index] <= '9') {
        index++;
      }
    }
    if (index < rawJson.length && (rawJson[index] === 'e' || rawJson[index] === 'E')) {
      index++;
      if (index < rawJson.length && (rawJson[index] === '+' || rawJson[index] === '-')) {
        index++;
      }
      while (index < rawJson.length && rawJson[index] >= '0' && rawJson[index] <= '9') {
        index++;
      }
    }

    const numStr = rawJson.substring(start, index);
    const parsed = Number(numStr);

    if (!Number.isFinite(parsed)) {
      throw new Rfc8785CanonicalizationError(`Non-finite number '${numStr}' at position ${start}`);
    }

    if (Number.isInteger(parsed)) {
      if (parsed < Number.MIN_SAFE_INTEGER || parsed > Number.MAX_SAFE_INTEGER) {
        throw new Rfc8785CanonicalizationError(
          `Integer '${numStr}' exceeds safe integer range [${Number.MIN_SAFE_INTEGER}, ${Number.MAX_SAFE_INTEGER}]`
        );
      }
    }

    return parsed;
  }

  function parseArray(): any[] {
    if (rawJson[index] !== '[') {
      throw new Rfc8785CanonicalizationError(`Expected '[' at position ${index}`);
    }
    index++; // skip '['
    const arr: any[] = [];
    skipWhitespace();

    if (index < rawJson.length && rawJson[index] === ']') {
      index++; // empty array
      return arr;
    }

    while (index < rawJson.length) {
      arr.push(parseValue());
      skipWhitespace();

      if (index < rawJson.length && rawJson[index] === ']') {
        index++;
        return arr;
      }
      if (index < rawJson.length && rawJson[index] === ',') {
        index++;
      } else {
        throw new Rfc8785CanonicalizationError(
          `Expected ',' or ']' in array at position ${index}`
        );
      }
    }

    throw new Rfc8785CanonicalizationError('Unterminated array in JSON input');
  }

  function parseObject(): Record<string, any> {
    if (rawJson[index] !== '{') {
      throw new Rfc8785CanonicalizationError(`Expected '{' at position ${index}`);
    }
    index++; // skip '{'
    const obj: Record<string, any> = {};
    const seenKeys = new Set<string>();
    skipWhitespace();

    if (index < rawJson.length && rawJson[index] === '}') {
      index++; // empty object
      return obj;
    }

    while (index < rawJson.length) {
      skipWhitespace();
      if (rawJson[index] !== '"') {
        throw new Rfc8785CanonicalizationError(
          `Expected string property key at position ${index}`
        );
      }
      const key = parseString();

      // Check for duplicate property names
      if (seenKeys.has(key)) {
        throw new Rfc8785CanonicalizationError(
          `RFC 8785 violation: Duplicate property name '${key}' detected in JSON object.`
        );
      }
      seenKeys.add(key);

      skipWhitespace();
      if (index >= rawJson.length || rawJson[index] !== ':') {
        throw new Rfc8785CanonicalizationError(`Expected ':' after key '${key}' at position ${index}`);
      }
      index++; // skip ':'

      const val = parseValue();
      obj[key] = val;

      skipWhitespace();
      if (index < rawJson.length && rawJson[index] === '}') {
        index++;
        return obj;
      }
      if (index < rawJson.length && rawJson[index] === ',') {
        index++;
      } else {
        throw new Rfc8785CanonicalizationError(
          `Expected ',' or '}' in object at position ${index}`
        );
      }
    }

    throw new Rfc8785CanonicalizationError('Unterminated object in JSON input');
  }

  const result = parseValue();
  skipWhitespace();
  if (index < rawJson.length) {
    throw new Rfc8785CanonicalizationError(`Unexpected trailing characters at position ${index}`);
  }
  return result;
}

/**
 * Validates, parses, and canonicalizes a raw JSON string according to RFC 8785.
 * Strictly rejects duplicate property names and lone surrogate characters.
 */
export function canonicalizeRawJson(rawJson: string): string {
  const parsed = parseJsonRejectingDuplicates(rawJson);
  return canonicalizeJson(parsed);
}
