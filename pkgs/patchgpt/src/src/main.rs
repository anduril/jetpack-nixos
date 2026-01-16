use std::io::Write;

use bytemuck::checked::from_bytes_mut;
use gpt_disk_types::{GptHeader, LbaLe};

fn show_help() {
    eprintln!("patchgpt [HEADER_PATH] [NEW_START] [BLOCK_SIZE]");
    eprintln!();
    eprintln!("Update GPT Header to live at NEW_START");
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() != 4 {
        show_help();
        return;
    }

    let mut table = std::fs::read(&args[1]).expect("Failed to read header");
    let new_start = args[2]
        .parse::<u64>()
        .unwrap_or_else(|_| panic!("Failed to parse {} as integer.", &args[2]));
    let block_size = args[3]
        .parse::<u64>()
        .unwrap_or_else(|_| panic!("Failed to parse {} as integer.", &args[3]));

    // Header is at the last block
    let header_start = table.len() as u64 - block_size;

    // Casting only works if size is identical
    let header_end = header_start + size_of::<GptHeader>() as u64;
    let bytes = &mut table[header_start as usize..header_end as usize];

    let header: &mut GptHeader = from_bytes_mut(bytes);

    header.my_lba = LbaLe::from_u64((new_start + header_start) / block_size);
    header.partition_entry_lba = LbaLe::from_u64(new_start / block_size);
    header.update_header_crc32();

    std::io::stdout()
        .write_all(&table)
        .expect("Failed to write stdout");
}
