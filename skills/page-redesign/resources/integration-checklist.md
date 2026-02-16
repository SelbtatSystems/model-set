# Integration Checklist

Quality gates for Phase 6 (Replace In-Place) of page redesign.

---

## Pre-Integration Verification

Before replacing the original file, verify:

### 1. Functionality Preservation

- [ ] **useQuery hooks**: All data fetching preserved with same query keys
- [ ] **useMutation hooks**: All data mutations preserved
- [ ] **Event handlers**: All user interactions functional
- [ ] **Form handling**: react-hook-form integration intact
- [ ] **Navigation**: All routing/navigation callbacks working

### 2. Context Integration

- [ ] **useAuth**: Authentication state accessible
- [ ] **useOrganization**: Organization context available
- [ ] **useNavigation**: Navigation context working
- [ ] **Custom contexts**: Any page-specific contexts preserved

### 3. Styling Compliance

- [ ] **CSS variables used**: No hardcoded hex colors
  - `--text-primary` for primary text
  - `--text-secondary` for secondary text
  - `--surface` for card backgrounds
  - `--accent` for primary actions
  - `--border` for borders
  - `--background` for page background
- [ ] **Dark mode support**: `.dark` class variants applied
- [ ] **Responsive breakpoints**: Mobile/tablet/desktop layouts work

### 4. TypeScript Compliance

- [ ] **No type errors**: `tsc --noEmit` passes
- [ ] **Props typed**: All component props use `Readonly<T>`
- [ ] **Interfaces preserved**: Original type definitions maintained

### 5. Architecture Standards

- [ ] **Logic in hooks**: Business logic extracted to custom hooks
- [ ] **No inline styles**: All styles via CSS classes or variables
- [ ] **Component modularity**: Sub-components properly extracted
- [ ] **Imports organized**: Grouped by type (react, external, internal)

---

## Post-Integration Testing

### Visual Verification

1. Navigate to page in browser
2. Compare layout to Stitch design
3. Test light mode appearance
4. Test dark mode appearance (toggle theme)
5. Test responsive breakpoints:
   - Desktop (1920px+)
   - Laptop (1366px)
   - Tablet (768px)
   - Mobile (375px)

### Functional Testing

1. Test all clickable elements
2. Test form inputs and validation
3. Test data loading states
4. Test error states
5. Test empty states
6. Verify API calls in Network tab

### Accessibility Testing

1. Tab through all interactive elements
2. Verify focus indicators visible
3. Check color contrast ratios
4. Test with screen reader (if available)

---

## Rollback Procedure

If issues found:

1. Original file backed up as `{PageName}.tsx.bak`
2. Restore: `mv {PageName}.tsx.bak {PageName}.tsx`
3. Restart dev server
4. Document issues for next iteration

---

## Sign-off

| Check | Status | Notes |
|-------|--------|-------|
| Functionality | [ ] Pass / [ ] Fail | |
| Context | [ ] Pass / [ ] Fail | |
| Styling | [ ] Pass / [ ] Fail | |
| TypeScript | [ ] Pass / [ ] Fail | |
| Architecture | [ ] Pass / [ ] Fail | |
| Visual | [ ] Pass / [ ] Fail | |
| Functional | [ ] Pass / [ ] Fail | |
| Accessibility | [ ] Pass / [ ] Fail | |

**Ready for production**: [ ] Yes / [ ] No

**Reviewer**: _______________
**Date**: _______________
