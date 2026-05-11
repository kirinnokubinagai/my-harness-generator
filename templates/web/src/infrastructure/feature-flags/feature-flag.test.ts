/**
 * 概要: feature-flag のテスト。boolean / percent / memoize の動作を検証する。
 */

import { describe, it, expect } from 'vitest';
import { isEnabled } from './feature-flag';

describe('isEnabled', () => {
  it('未定義のフラグは false を返すこと', () => {
    expect(isEnabled({ FEATURE_FLAGS: '' }, 'unknown')).toBe(false);
    expect(isEnabled({}, 'unknown')).toBe(false);
  });

  it('真偽値フラグが期待通り返ること', () => {
    const env = { FEATURE_FLAGS: 'a=true,b=false' };
    expect(isEnabled(env, 'a')).toBe(true);
    expect(isEnabled(env, 'b')).toBe(false);
  });

  it('% rollout が安定 hash で評価されること', () => {
    const env = { FEATURE_FLAGS: 'x=50%' };
    const a = isEnabled(env, 'x', { userId: 'user-1' });
    const b = isEnabled(env, 'x', { userId: 'user-1' });
    expect(a).toBe(b);
  });

  it('0% は全員 false、100% は全員 true になること', () => {
    expect(isEnabled({ FEATURE_FLAGS: 'never=0%' }, 'never', { userId: 'a' })).toBe(false);
    expect(isEnabled({ FEATURE_FLAGS: 'always=100%' }, 'always', { userId: 'a' })).toBe(true);
  });

  it('同じ env オブジェクトに対して memoize されること (副作用観測)', () => {
    const env = { FEATURE_FLAGS: 'x=true' };
    isEnabled(env, 'x');
    const before = env.FEATURE_FLAGS;
    env.FEATURE_FLAGS = 'x=false';
    expect(isEnabled(env, 'x')).toBe(true);
    env.FEATURE_FLAGS = before;
  });
});
