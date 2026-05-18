// Inyecta la llave de desarrollo antes de que cualquier módulo cargue.
// defineSecret("MASTER_AES_KEY").value() lee process.env["MASTER_AES_KEY"]
// cuando está definida — sin necesidad de conectarse a GCP Secret Manager.
//
// IMPORTANTE: NO se activa FUNCTIONS_EMULATOR, por lo que IS_EMULATOR = false
// y los guards RBAC (assertAdmin, assertAuthenticated) rechazan correctamente
// las solicitudes no autenticadas en los tests de seguridad.
process.env["MASTER_AES_KEY"] = "omnisport-ai-super-secret-dev-key";
