# SAM uses this Makefile to bundle pre-built Lambda functions.
# TypeScript must be compiled BEFORE running `sam build`.
# Run: cd lambda && npm run build   (then cd .. && sam build)

build-SubmitReportFunction: build-common
build-GetNearbyReportsFunction: build-common
build-GetVenueReportsFunction: build-common
build-GetUserProfileFunction: build-common
build-UpdateUserProfileFunction: build-common
build-GetProfileUploadUrlFunction: build-common

build-common:
	cp -r dist $(ARTIFACTS_DIR)/dist
	cp package.json $(ARTIFACTS_DIR)/
	cd $(ARTIFACTS_DIR) && npm install --omit=dev
