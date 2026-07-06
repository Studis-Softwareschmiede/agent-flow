import { test, expect } from '@playwright/test';
import testData from './example.data.json';

/**
 * Covers (regression-playwright-conventions): AC2, AC3
 * @file Example data-driven test suite
 *
 * Illustrates the Fabrik regression-test convention: test file + data table (JSON)
 * side-by-side. The test iterates over the JSON table, running the same test logic
 * for each row.
 */

test.describe('Board area tests (example suite)', () => {
  // Data-driven: iterate over JSON table
  testData.forEach((testCase) => {
    test(`should handle area: ${testCase.area_id}`, async ({ page }) => {
      // Example: verify that each area from the table is recognized
      expect(testCase.area_id).toBeDefined();
      expect(testCase.area_id).toMatch(/^[a-z][a-z0-9-]*$/); // kebab-case

      // Example: verify description is non-empty
      expect(testCase.description).toBeTruthy();
      expect(testCase.description.length).toBeGreaterThan(0);

      // Example: verify order is a positive integer
      expect(typeof testCase.order).toBe('number');
      expect(testCase.order).toBeGreaterThan(0);
    });
  });

  test('board area schema is valid', () => {
    // Summary test: verify overall table structure
    expect(Array.isArray(testData)).toBe(true);
    expect(testData.length).toBeGreaterThan(0);

    // All rows have required fields
    testData.forEach((row) => {
      expect(row).toHaveProperty('area_id');
      expect(row).toHaveProperty('description');
      expect(row).toHaveProperty('order');
    });
  });
});
