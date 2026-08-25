#!/usr/bin/env bash
# ============================================================
# TLS Certificate Generation Script for Wisecow
# Generates self-signed certificates for local development
# and creates the Kubernetes TLS secret
# ============================================================

set -euo pipefail

# Configuration
CERT_DIR="${CERT_DIR:-./certs}"
DOMAIN="${DOMAIN:-wisecow.local}"
NAMESPACE="${NAMESPACE:-wisecow}"
SECRET_NAME="${SECRET_NAME:-wisecow-tls}"
DAYS_VALID="${DAYS_VALID:-365}"

echo "🔐 Generating TLS certificates for: ${DOMAIN}"
echo "   Output directory: ${CERT_DIR}"
echo "   Valid for: ${DAYS_VALID} days"

# Create certificate directory
mkdir -p "${CERT_DIR}"

# ============================================================
# Step 1: Generate CA (Certificate Authority) key and cert
# ============================================================
echo ""
echo "📝 Step 1: Generating Certificate Authority (CA)..."

openssl genrsa -out "${CERT_DIR}/ca.key" 2048 2>/dev/null

openssl req -new -x509 -days "${DAYS_VALID}" -key "${CERT_DIR}/ca.key" \
    -out "${CERT_DIR}/ca.crt" \
    -subj "/C=US/ST=DevOps/L=Training/O=Accuknox/CN=Accuknox-CA" \
    2>/dev/null

echo "   ✅ CA certificate created: ${CERT_DIR}/ca.crt"

# ============================================================
# Step 2: Generate server key and CSR (Certificate Signing Request)
# ============================================================
echo ""
echo "📝 Step 2: Generating server key and CSR..."

openssl genrsa -out "${CERT_DIR}/server.key" 2048 2>/dev/null

openssl req -new -key "${CERT_DIR}/server.key" \
    -out "${CERT_DIR}/server.csr" \
    -subj "/C=US/ST=DevOps/L=Training/O=Accuknox/CN=${DOMAIN}" \
    2>/dev/null

echo "   ✅ Server key and CSR created"

# ============================================================
# Step 3: Create SAN (Subject Alternative Name) extension file
# ============================================================
echo ""
echo "📝 Step 3: Creating SAN extension for ${DOMAIN}..."

cat > "${CERT_DIR}/san.ext" << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=@alt_names

[alt_names]
DNS.1=${DOMAIN}
DNS.2=wisecow-service
DNS.3=wisecow-service.${NAMESPACE}
DNS.4=wisecow-service.${NAMESPACE}.svc
DNS.5=wisecow-service.${NAMESPACE}.svc.cluster.local
DNS.6=localhost
IP.1=127.0.0.1
EOF

echo "   ✅ SAN extension created"

# ============================================================
# Step 4: Generate server certificate signed by CA
# ============================================================
echo ""
echo "📝 Step 4: Generating server certificate..."

openssl x509 -req -days "${DAYS_VALID}" \
    -in "${CERT_DIR}/server.csr" \
    -CA "${CERT_DIR}/ca.crt" \
    -CAkey "${CERT_DIR}/ca.key" \
    -CAcreateserial \
    -out "${CERT_DIR}/server.crt" \
    -extfile "${CERT_DIR}/san.ext" \
    2>/dev/null

echo "   ✅ Server certificate created: ${CERT_DIR}/server.crt"

# ============================================================
# Step 5: Create Kubernetes TLS Secret
# ============================================================
echo ""
echo "📝 Step 5: Creating Kubernetes TLS secret..."

# Create namespace if it doesn't exist
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null

# Create the TLS secret
kubectl create secret tls "${SECRET_NAME}" \
    --namespace="${NAMESPACE}" \
    --cert="${CERT_DIR}/server.crt" \
    --key="${CERT_DIR}/server.key" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "   ✅ TLS secret '${SECRET_NAME}' created in namespace '${NAMESPACE}'"

# ============================================================
# Summary
# ============================================================
echo ""
echo "============================================"
echo "🎉 TLS Certificate Generation Complete!"
echo "============================================"
echo ""
echo "Certificates generated in: ${CERT_DIR}/"
echo "  - ca.crt (Certificate Authority)"
echo "  - ca.key (CA Private Key)"
echo "  - server.crt (Server Certificate)"
echo "  - server.key (Server Private Key)"
echo ""
echo "Kubernetes secret: ${SECRET_NAME} in namespace ${NAMESPACE}"
echo ""
echo "To verify the certificate:"
echo "  openssl x509 -in ${CERT_DIR}/server.crt -text -noout | grep -A3 'Subject Alternative Name'"
echo ""
echo "To use in Ingress, ensure your Ingress resource references:"
echo "  secretName: ${SECRET_NAME}"
