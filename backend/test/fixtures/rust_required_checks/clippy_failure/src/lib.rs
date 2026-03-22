use std::collections::HashMap;

pub fn insert_with_contains_key(cache: &mut HashMap<String, u32>, key: String, value: u32) {
    if !cache.contains_key(&key) {
        cache.insert(key, value);
    }
}
