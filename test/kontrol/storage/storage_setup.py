import json
import sys

def is_scalar_type(var_type):
    return var_type == 't_bool' or var_type == 't_address' or var_type.startswith('t_uint') or var_type.startswith('t_enum') or var_type.startswith('t_contract') or var_type.startswith('t_userDefinedValueType')

def print_constant(name, value):
    print(f'    uint256 public constant {name} = {value};')

def print_constants_for_storage_variable(prefix, slot, var, types):
    print_constant(f'{prefix}_SLOT', slot)
    print_constant(f'{prefix}_OFFSET', var['offset'])
    print_constant(f'{prefix}_SIZE', types[var['type']]['numberOfBytes'])

def print_constants_for_storage_variables_recursive(prefix, slot, var, types):
    updated_prefix = prefix + '_' + var['label'].replace('_', '').upper()
    updated_slot = slot + int(var['slot'])
    var_type = var['type']

    if is_scalar_type(var_type) or var_type == 't_bytes_storage' or var_type.startswith('t_array') or var_type.startswith('t_mapping'):
        print_constants_for_storage_variable(updated_prefix, updated_slot, var, types)
    elif var_type.startswith('t_struct'):
        for member in types[var_type]['members']:
            print_constants_for_storage_variables_recursive(updated_prefix, updated_slot, member, types)

def main():
    json_filename = sys.argv[1]
    solidity_version = sys.argv[2]
    contract_name = sys.argv[3]

    with open(json_filename, 'r') as file:
        data = json.load(file)
        storage = data['storage']
        types = data['types']

        print(f'pragma solidity {solidity_version};')
        print()
        print(f'library {contract_name}StorageConstants {{')

        for storage_var in storage:
            print_constants_for_storage_variables_recursive('STORAGE', 0, storage_var, types)

        for var_type in types:
            if var_type.startswith('t_struct'):
                prefix = types[var_type]['label'].replace(' ', '_').replace('.', '_').upper()
                print_constant(prefix + '_SIZE', types[var_type]['numberOfBytes'])

                for member in types[var_type]['members']:
                    print_constants_for_storage_variables_recursive(prefix, 0, member, types)

        print('}')

sys.exit(main())



    
