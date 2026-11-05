#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${FIREBASE_PROJECT_ID:-kelasagara-staging}"
echo "Deploying Firestore security rules and vector indexes to ${PROJECT_ID}..."
firebase deploy --only firestore:rules,firestore:indexes --project="${PROJECT_ID}"
