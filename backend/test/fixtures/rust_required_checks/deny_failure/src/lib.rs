pub fn decode_value(input: &str) -> Result<Vec<u8>, base64::DecodeError> {
    base64::decode(input)
}
